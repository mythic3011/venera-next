import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { mkdtemp,mkdir,writeFile,rm,readFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createHash } from "node:crypto";
import { initializeFreshV2Database,loadReviewedFreshV2Sql } from
  "../src/schema-bootstrap.mjs";
import { createHostGestureAuthority } from
  "../../../tools/legacy-import/trusted-gesture.mjs";
import { TrustedLinuxMediaRootGrants } from
  "../../../tools/legacy-import/media-root-linux.mjs";
import { createTrustedV2StorageWriter,V2StorageWriteError } from
  "../src/storage-writer-linux.mjs";

const OWNER="storage-test-principal";
const DATASET="b1559f3b-6834-4b64-99ab-725369019d2a";
const PNG=Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),
  Buffer.from("synthetic image data for v2 storage object test")]);
const hex=bytes=>createHash("sha256").update(bytes).digest("hex");
async function fixture(t,{gesture=async({challenge})=>challenge,
  fault=null}={}){
 const managed=await mkdtemp(join(tmpdir(),"v2-managed-storage-"));
 const source=await mkdtemp(join(tmpdir(),"v2-image-source-"));
 t.after(async()=>{
   await rm(managed,{recursive:true,force:true});
   await rm(source,{recursive:true,force:true});
 });
 await mkdir(join(source,"images"),{mode:0o700});
 await writeFile(join(source,"images","cover.png"),PNG);
 const db=new DatabaseSync(":memory:");
 t.after(()=>db.close());
 initializeFreshV2Database(db,await loadReviewedFreshV2Sql());
 const grants=new TrustedLinuxMediaRootGrants();
 const grant=await grants.grantFromTrustedPicker({
   ownerScopeId:OWNER,datasetId:DATASET,
   requestTrustedDirectory:async()=>source
 });
 t.after(async()=>{await grants.revoke({
   grant,ownerScopeId:OWNER,datasetId:DATASET
 }).catch(()=>{});});
 const gestureAuthority=createHostGestureAuthority({requestConfirmation:gesture});
 const create=()=>createTrustedV2StorageWriter({
   canonicalDb:db,appDataDirectory:managed,
   trustedMediaRootResolver:grants,gestureAuthority,
   checkpoint:async point=>{
     if(point===fault)throw new Error("FI_"+point);
   }
 });
 const writer=await create();
 t.after(()=>writer.close());
 const plan=()=>writer.inspectGrantedImage({
   ownerScopeId:OWNER,datasetId:DATASET,mediaGrant:grant,
   relativeSegments:["images","cover.png"]
 });
 return {db,managed,source,grants,grant,writer,create,plan};
}
function count(db,table){
 return db.prepare("SELECT COUNT(*) AS n FROM "+table).get().n;
}
test("after separate gesture, stage verify promote and commit detached object + authority",async t=>{
 const f=await fixture(t);
 const ready=await f.plan();
 assert.equal(ready.preview.scope,"storage_object_only");
 assert.equal(ready.preview.canImportLegacy,false);
 assert.equal(count(f.db,"v2_storage_write_journal"),0);
 assert.equal(count(f.db,"storage_objects"),0);
 const outcome=await f.writer.approveAndWrite(ready);
 assert.equal(outcome.status,"storage_object_committed");
 assert.equal(outcome.canAttachContent,false);
 assert.equal(count(f.db,"v2_storage_write_journal"),1);
 assert.equal(count(f.db,"storage_objects"),1);
 assert.equal(count(f.db,"storage_placements"),1);
 const object=f.db.prepare("SELECT * FROM storage_objects").get();
 const placement=f.db.prepare("SELECT * FROM storage_placements").get();
 const journal=f.db.prepare("SELECT * FROM v2_storage_write_journal").get();
 assert.equal(object.content_hash,hex(PNG));
 assert.equal(object.size_bytes,PNG.length);
 assert.equal(object.mime_type,"image/png");
 assert.equal(placement.role,"authority");
 assert.equal(placement.sync_status,"synced");
 assert.equal(journal.state,"committed");
 assert.equal(journal.authorization_scope,"storage_object_only");
 assert.equal((await readFile(join(f.managed,"v2-objects",placement.object_key))).compare(PNG),0);
 assert.equal(count(f.db,"contents"),0);
 assert.equal(count(f.db,"content_units"),0);
 assert.equal(count(f.db,"reading_sessions"),0);
 assert.deepEqual(await f.writer.auditRecovery(),
   [{journalId:outcome.journalId,status:"healthy"}]);
 await assert.rejects(f.writer.approveAndWrite(ready),
   e=>e instanceof V2StorageWriteError&&e.code==="V2_STORAGE_PLAN_INVALID");
});
test("cancelled gesture cannot write intent or filesystem objects",async t=>{
 const f=await fixture(t,{gesture:async()=>""});
 await assert.rejects(f.writer.approveAndWrite(await f.plan()));
 assert.equal(count(f.db,"v2_storage_write_journal"),0);
 assert.equal(count(f.db,"storage_objects"),0);
 assert.equal((await f.writer.auditRecovery()).length,0);
});
test("revoked OS media grant during human approval denies before journal",async t=>{
 let f;
 f=await fixture(t,{gesture:async({challenge})=>{
   await f.grants.revoke({grant:f.grant,ownerScopeId:OWNER,datasetId:DATASET});
   return challenge;
 }});
 await assert.rejects(f.writer.approveAndWrite(await f.plan()));
 assert.equal(count(f.db,"v2_storage_write_journal"),0);
});
test("source bytes modified during confirmation deny changed snapshot without write",async t=>{
 let f;
 f=await fixture(t,{gesture:async({challenge})=>{
   await writeFile(join(f.source,"images","cover.png"),
     Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),
       Buffer.from("changed bytes after user preview")]));
   return challenge;
 }});
 await assert.rejects(f.writer.approveAndWrite(await f.plan()),
   e=>e instanceof V2StorageWriteError&&e.code==="V2_STORAGE_INPUT_CHANGED");
 assert.equal(count(f.db,"v2_storage_write_journal"),0);
});
for(const [failAt,expected,objects] of [
 ["after_intent","missing_uncommitted_review",0],
 ["after_stage","staged_uncommitted_review",0],
 ["after_promotion","promoted_uncommitted_review",0],
 ["before_visibility_commit","promoted_uncommitted_review",0],
 ["after_visibility_commit","healthy",1],
]){
 test("crash checkpoint "+failAt+" leaves recoverable non-destructive evidence",async t=>{
  const f=await fixture(t,{fault:failAt});
  await assert.rejects(f.writer.approveAndWrite(await f.plan()),
    new RegExp("FI_"+failAt));
  assert.equal(count(f.db,"storage_objects"),objects);
  assert.equal(count(f.db,"storage_placements"),objects);
  assert.equal(count(f.db,"contents"),0);
  const rows=await f.writer.auditRecovery();
  assert.equal(rows.length,1);
  assert.equal(rows[0].status,expected);
  // Audit must never unlink either stages or already-promoted blobs.
  assert.deepEqual(await f.writer.auditRecovery(),rows);
 });
}
test("postcommit missing or mutated managed blob reports unavailable, never healthy",async t=>{
 const f=await fixture(t);
 const result=await f.writer.approveAndWrite(await f.plan());
 const row=f.db.prepare(
  "SELECT object_key FROM v2_storage_write_journal WHERE id=?"
 ).get(result.journalId);
 await writeFile(join(f.managed,"v2-objects",row.object_key),
   Buffer.from("corrupt after prior successful commit"));
 assert.deepEqual(await f.writer.auditRecovery(),
  [{journalId:result.journalId,status:"storage_unavailable"}]);
 assert.equal(count(f.db,"storage_objects"),1); // preserve repair evidence
});
test("legacy plan-only journal cannot authorize this independent writer",async t=>{
 const f=await fixture(t);
 assert.equal(count(f.db,"legacy_asset_journal"),0);
 await f.writer.approveAndWrite(await f.plan());
 assert.equal(count(f.db,"legacy_import_batches"),0);
 assert.equal(count(f.db,"legacy_asset_journal"),0);
 assert.equal(count(f.db,"legacy_record_mappings"),0);
 const row=f.db.prepare("SELECT authorization_scope FROM v2_storage_write_journal").get();
 assert.equal(row.authorization_scope,"storage_object_only");
 assert.throws(()=>f.db.prepare(
   "UPDATE v2_storage_write_journal SET authorization_scope='plan_only'"
 ).run(),/CHECK constraint failed/);
});
