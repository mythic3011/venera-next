import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { TrustedLegacyAssetIntentService, AssetPreparationError } from "../asset-intent.mjs";
import { TrustedLegacyApprovalService } from "../approval-gate.mjs";
import { TrustedSnapshotLeaseRegistry } from "../snapshot-lease.mjs";
import { createHostGestureAuthority } from "../trusted-gesture.mjs";

const OWNER="v2-owner";
const DATASET="23354d4b-b8d5-4fe9-a133-f9a07a8be0d9";
const ROW_DIGEST="d".repeat(64);
function key(id="comic1") {
  return {datasetId:DATASET,fileRole:"local.db",tableKind:"comics",
    legacyTypeKey:"1",scopeKey:"",legacyId:id};
}
const hash=v=>createHash("sha256").update(v).digest("hex");
const DOC=new URL("../../../docs/design/v2/02_DATABASE_SCHEMA.md",import.meta.url);
const s=readFileSync(DOC,"utf8");
const from=s.indexOf("CREATE TABLE legacy_import_datasets (");
const to=s.indexOf("~~~",from);
assert.ok(from>=0&&to>from);
const schema=s.slice(from,to);
const DATA=Buffer.from("SQLite format 3\0fixture");
const MEDIA=Buffer.from("synthetic approved media bytes in memory, never a filesystem path");

async function setup(t,{gesture=async ({challenge})=>challenge}={}) {
  const db=new DatabaseSync(":memory:");
  t.after(()=>db.close());
  db.exec("PRAGMA foreign_keys=ON");
  for(const tbl of ["contents","content_sections","content_units",
    "user_collections","user_collection_items","storage_objects"])
    db.exec("CREATE TABLE "+tbl+"(id TEXT PRIMARY KEY)");
  db.exec(schema);
  const leases=new TrustedSnapshotLeaseRegistry();
  const {leaseRef}=leases.issue({
    ownerScopeId:OWNER,datasetId:DATASET,
    inputs:[{role:"local.db",bytes:DATA}],
    recordProofs:[{version:1,role:"local.db",snapshotSha256:hash(DATA),
      records:[{recordDigest:ROW_DIGEST,fileRole:"local.db",
        tableKind:"comics",scopeKey:"",legacyTypeKey:"1",legacyId:"comic1"}]
    }]
  });
  const gate=new TrustedLegacyApprovalService({
    canonicalDb:db,snapshotLeaseRegistry:leases,
    verifyTrustedUserGesture:async()=>true // test-only fixture
  });
  const now=new Date().toISOString();
  db.prepare("INSERT INTO legacy_import_datasets(id,owner_scope_id,display_label,state,created_at,updated_at) VALUES(?,?,?,'active',?,?)")
    .run(DATASET,OWNER,"fixture",now,now);
  const plan=gate.createPlanForLease({
    ownerScopeId:OWNER,datasetId:DATASET,leaseRef,policyRevision:"l0-evidence-only-v1"
  });
  const approved=await gate.approve({plan,gesture:{mock:true},expectedPlanDigest:plan.planDigest});
  const gestureAuthority=createHostGestureAuthority({requestConfirmation:gesture});
  const service=new TrustedLegacyAssetIntentService({
    canonicalDb:db,snapshotLeaseRegistry:leases,gestureAuthority
  });
  return {db,leases,leaseRef,service,batchId:approved.batchId};
}
function inspect(fixture,overrides={}) {
  return fixture.service.inspect({
    ownerScopeId:OWNER,batchId:fixture.batchId,key:key(),
    recordDigest:ROW_DIGEST,assetBytes:MEDIA,...overrides
  });
}
function rows(db,table) {return db.prepare("SELECT COUNT(*) AS n FROM "+table).get().n;}
test("asset preparation requires separate human gesture; only planned journal appears",async t=>{
  const f=await setup(t);
  const {plan,preview}=inspect(f);
  assert.deepEqual(preview.actionScope,"plan_only");
  assert.equal(preview.canCommit,false);
  assert.equal(preview.canCopy,false);
  assert.equal(rows(f.db,"legacy_asset_journal"),0);
  const response=await f.service.authorizeAndRecordIntent({plan,preview});
  assert.equal(response.status,"asset_intent_planned");
  const recorded=f.db.prepare("SELECT state,authorization_scope,expected_sha256,expected_bytes,staging_ref,committed_storage_id FROM legacy_asset_journal").get();
  assert.equal(recorded.state,"planned");
  assert.equal(recorded.authorization_scope,"plan_only");
  assert.equal(recorded.expected_sha256,hash(MEDIA));
  assert.equal(recorded.expected_bytes,MEDIA.length);
  assert.ok(recorded.staging_ref.startsWith("intent:"));
  assert.equal(recorded.committed_storage_id,null);
  for(const table of ["contents","storage_objects","content_sections","content_units"])
    assert.equal(rows(f.db,table),0);
  assert.throws(()=>f.db.prepare(
    "UPDATE legacy_asset_journal SET authorization_scope='content_import'"
  ).run(),/CHECK constraint failed/);
  await assert.rejects(f.service.authorizeAndRecordIntent({plan,preview}),
    e=>e.code==="ASSET_PLAN_INVALID");
});
test("forged IDs, row digests, cross-owner and removed approval deny before journal",async t=>{
  const f=await setup(t);
  for(const attempt of [
    {key:key("fake")},
    {key:{...key(),legacyTypeKey:"2"}},
    {recordDigest:"1".repeat(64)},
    {ownerScopeId:"other"},
    {key:{...key(),fileRole:"history.db",tableKind:"history"}}
  ])assert.throws(()=>inspect(f,attempt),AssetPreparationError);
  assert.equal(rows(f.db,"legacy_asset_journal"),0);
});
test("cancelled or revoked evidence Batch cannot mint asset intent",async t=>{
  const f=await setup(t);
  f.db.prepare("UPDATE legacy_import_batches SET state='cancelled',completed_at=? WHERE id=?")
    .run(new Date().toISOString(),f.batchId);
  assert.throws(()=>inspect(f),e=>e.code==="ASSET_EVIDENCE_APPROVAL_REQUIRED");
  assert.equal(rows(f.db,"legacy_asset_journal"),0);
});
test("stale snapshot lease cannot authorize asset intent",async t=>{
  const f=await setup(t);
  f.leases.revoke({leaseRef:f.leaseRef,ownerScopeId:OWNER,datasetId:DATASET});
  assert.throws(()=>inspect(f),e=>e.code==="ASSET_RECORD_UNATTESTED");
});
test("gesture rejects and leaves canonical asset journal empty",async t=>{
  const f=await setup(t,{gesture:async()=>""});
  const {plan,preview}=inspect(f);
  await assert.rejects(f.service.authorizeAndRecordIntent({plan,preview}));
  assert.equal(rows(f.db,"legacy_asset_journal"),0);
  await assert.rejects(f.service.authorizeAndRecordIntent({plan,preview}),
    e=>e.code==="ASSET_PLAN_INVALID");
});
test("revoking lease during human confirmation denies with no DB write",async t=>{
  let fixture;
  fixture=await setup(t,{gesture:async({challenge})=>{
    fixture.leases.revoke({leaseRef:fixture.leaseRef,ownerScopeId:OWNER,datasetId:DATASET});
    return challenge;
  }});
  const {plan,preview}=inspect(fixture);
  await assert.rejects(fixture.service.authorizeAndRecordIntent({plan,preview}),
    e=>e.code==="ASSET_RECORD_UNATTESTED");
  assert.equal(rows(fixture.db,"legacy_asset_journal"),0);
});
test("unknown or over-budget media bytes cannot create a plan",async t=>{
  const f=await setup(t);
  for(const bytes of ["path to /home/user",Buffer.alloc(0),Buffer.alloc(64*1024*1024+1)])
    assert.throws(()=>inspect(f,{assetBytes:bytes}),AssetPreparationError);
  assert.equal(rows(f.db,"legacy_asset_journal"),0);
});
