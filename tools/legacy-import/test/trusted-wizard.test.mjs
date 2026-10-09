import test from "node:test";
import assert from "node:assert/strict";
import { createHostGestureAuthority, createTTYGestureAuthority, WizardGestureError } from "../trusted-gesture.mjs";
import { runTrustedEvidenceWizard, LegacyWizardError } from "../trusted-wizard.mjs";
import { TrustedSnapshotLeaseRegistry } from "../snapshot-lease.mjs";
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";

const OWNER="local-test-owner";
const DATASET="b1c55d44-ad15-4519-bdd0-33bf01889f81";
const DIGEST="a".repeat(64);
const CTX={ownerScopeId:OWNER,datasetId:DATASET,planDigest:DIGEST};
const DOC=new URL("../../../docs/design/v2/02_DATABASE_SCHEMA.md",import.meta.url);
const SQL=readFileSync(DOC,"utf8");
const start=SQL.indexOf("CREATE TABLE legacy_import_datasets (");
const end=SQL.indexOf("~~~",start);
assert.ok(start>=0 && end>start);
function setup(t) {
  const db=new DatabaseSync(":memory:");
  t.after(()=>db.close());
  db.exec("PRAGMA foreign_keys=ON");
  for(const table of ["contents","content_sections","content_units",
    "user_collections","user_collection_items","storage_objects"])
    db.exec("CREATE TABLE "+table+"(id TEXT PRIMARY KEY)");
  db.exec(SQL.slice(start,end));
  return db;
}
function count(db,table){
  return db.prepare("SELECT COUNT(*) AS n FROM "+table).get().n;
}
function preview(){
  const roles=["local.db","history.db","local_favorite.db",
    "appdata.json","implicitData.json"];
  return {status:"preview_only",canCommit:false,
    files:roles.map((role,i)=>({
      role,status:i===0?"inspected":"missing",records:i===0?1:0,
      deferred:0,reviewRequired:i===0?1:0
    }))};
}
function snapshotter(r){
  return async ({ownerScopeId,datasetId,snapshotLeaseRegistry})=>{
    const bytes=Buffer.from("SQLite format 3\0one");
    const digest=createHash("sha256").update(bytes).digest("hex");
    const {leaseRef}=snapshotLeaseRegistry.issue({
      ownerScopeId,datasetId,inputs:[{role:"local.db",bytes}],
      recordProofs:[{version:1,role:"local.db",snapshotSha256:digest,
        records:[{fileRole:"local.db",tableKind:"comics",scopeKey:"",
          legacyTypeKey:"1",legacyId:"one",recordDigest:DIGEST}]}]
    });
    r.leaseRef=leaseRef;r.datasetId=datasetId;
    return {preview:preview(),leaseRef};
  };
}
test("host gesture phrase is scoped and one-shot; forged objects fail",async()=>{
  const g=createHostGestureAuthority({
    requestConfirmation:async ({challenge})=>challenge
  });
  const issued=await g.confirm(CTX,preview());
  assert.equal(await g.verifyTrustedUserGesture({},CTX),false);
  assert.equal(await g.verifyTrustedUserGesture(issued,{...CTX,planDigest:"b".repeat(64)}),false);
  assert.equal(await g.verifyTrustedUserGesture(issued,CTX),false);
  const second=await g.confirm(CTX,preview());
  assert.equal(await g.verifyTrustedUserGesture(second,CTX),true);
  assert.equal(await g.verifyTrustedUserGesture(second,CTX),false);
});
test("real terminal verifier refuses non-TTY, no headless approval shortcut",()=>{
  assert.throws(()=>createTTYGestureAuthority(),
    e=>e instanceof WizardGestureError && e.code==="WIZARD_TRUSTED_TTY_REQUIRED");
  const cli=new URL("../wizard-console.mjs",import.meta.url);
  const p=spawnSync(process.execPath,[cli.pathname,"--source","/nothing",
    "--canonical-db","/nothing2","--dataset-label","test"],{encoding:"utf8"});
  assert.notEqual(p.status,0);
  assert.match(p.stderr,/WIZARD_TRUSTED_TTY_REQUIRED/);
  assert.ok(!p.stdout.includes("evidence_approved"));
});
test("gesture fails closed for wrong phrase, cancellation, expired challenge",async()=>{
  for(const input of ["", "APPROVE", "yes", "true"]){
    const g=createHostGestureAuthority({
      requestConfirmation:async()=>input
    });
    await assert.rejects(g.confirm(CTX,preview()),WizardGestureError);
  }
  const cancel=createHostGestureAuthority({
    requestConfirmation:async()=>{throw new Error("cancelled");}
  });
  await assert.rejects(cancel.confirm(CTX,preview()),
    e=>e.code==="WIZARD_GESTURE_CANCELLED");
  let now=0;
  const late=createHostGestureAuthority({
    now:()=>now,requestConfirmation:async({challenge})=>{
      now=61000;return challenge;
    }
  });
  await assert.rejects(late.confirm(CTX,preview()),
    e=>e.code==="WIZARD_GESTURE_REJECTED");
});
test("concurrent wizard confirmation cannot open a second gesture",async()=>{
 let release;
 const block=new Promise(r=>{release=r;});
 const gate=createHostGestureAuthority({
   requestConfirmation:async({challenge})=>{await block;return challenge;}
 });
 const first=gate.confirm(CTX,preview());
 await assert.rejects(gate.confirm(CTX,preview()),
   e=>e.code==="WIZARD_GESTURE_INVALID");
 release();
 const gesture=await first;
 assert.equal(await gate.verifyTrustedUserGesture(gesture,CTX),true);
});
test("approved evidence-only wizard creates new Dataset + Batch together, never content",async t=>{
  const db=setup(t),registry=new TrustedSnapshotLeaseRegistry(),state={};
  const gesture=createHostGestureAuthority({
    requestConfirmation:async({challenge})=>challenge
  });
  const result=await runTrustedEvidenceWizard({
    selectedDirectory:"/dummy",ownerScopeId:OWNER,canonicalDb:db,
    datasetIntent:"new",newDatasetLabel:"Old laptop",
    snapshotLeaseRegistry:registry,gestureAuthority:gesture,
    snapshotter:snapshotter(state)
  });
  assert.equal(result.status,"evidence_approved");
  assert.equal(result.scope,"evidence_only");
  assert.equal(result.importedContents,0);
  assert.equal(result.importedSettings,0);
  assert.equal(result.importedReaderPositions,0);
  assert.equal(count(db,"legacy_import_datasets"),1);
  assert.equal(count(db,"legacy_import_batches"),1);
  assert.equal(count(db,"legacy_record_mappings"),0);
  assert.equal(count(db,"contents"),0);
  assert.equal(db.prepare("SELECT state FROM legacy_import_batches").get().state,"approved");
  assert.equal(db.prepare("SELECT policy_revision FROM legacy_import_batches").get().policy_revision,
    "l0-evidence-only-v1");
  assert.equal(registry.getManifest({leaseRef:state.leaseRef,
    ownerScopeId:OWNER,datasetId:state.datasetId}).length,1);
});
test("user cancellation does not persist approval and always revokes private lease",async t=>{
  const db=setup(t),registry=new TrustedSnapshotLeaseRegistry(),state={};
  const gesture=createHostGestureAuthority({
    requestConfirmation:async()=>"" // cancel
  });
  await assert.rejects(runTrustedEvidenceWizard({
    selectedDirectory:"/dummy",ownerScopeId:OWNER,canonicalDb:db,
    datasetIntent:"new",newDatasetLabel:"Old laptop",
    snapshotLeaseRegistry:registry,gestureAuthority:gesture,
    snapshotter:snapshotter(state)
  }),e=>e.code==="WIZARD_GESTURE_REJECTED");
  assert.equal(count(db,"legacy_import_datasets"),0);
  assert.equal(count(db,"legacy_import_batches"),0);
  assert.equal(registry.getManifest({
    leaseRef:state.leaseRef,ownerScopeId:OWNER,datasetId:state.datasetId}),null);
});
test("revocation during TTY confirmation rejects Batch and never persists a Dataset",async t=>{
 const db=setup(t),registry=new TrustedSnapshotLeaseRegistry(),state={};
 const gesture=createHostGestureAuthority({
   requestConfirmation:async({challenge})=>{
     registry.revoke({leaseRef:state.leaseRef,
       ownerScopeId:OWNER,datasetId:state.datasetId});
     return challenge;
   }
 });
 await assert.rejects(runTrustedEvidenceWizard({
   selectedDirectory:"/dummy",ownerScopeId:OWNER,canonicalDb:db,
   datasetIntent:"new",newDatasetLabel:"Old laptop",
   snapshotLeaseRegistry:registry,gestureAuthority:gesture,
   snapshotter:snapshotter(state)
 }),e=>e.code==="LEGACY_APPROVAL_STALE");
 assert.equal(count(db,"legacy_import_datasets"),0);
 assert.equal(count(db,"legacy_import_batches"),0);
});
test("existing Dataset belonging to another owner is denied without snapshot",async t=>{
 const db=setup(t),registry=new TrustedSnapshotLeaseRegistry();
 const now=new Date().toISOString();
 db.prepare("INSERT INTO legacy_import_datasets VALUES(?,? ,?,'active',?,?)")
 .run(DATASET,"different-owner","Old install",now,now);
 let touched=false;
 await assert.rejects(runTrustedEvidenceWizard({
   selectedDirectory:"/dummy",ownerScopeId:OWNER,canonicalDb:db,
   datasetIntent:"existing",datasetId:DATASET,
   snapshotLeaseRegistry:registry,gestureAuthority:createHostGestureAuthority({
     requestConfirmation:async({challenge})=>challenge
   }),
   snapshotter:async()=>{touched=true;throw new Error("should not call");}
 }),e=>e instanceof LegacyWizardError&&e.code==="WIZARD_DATASET_NOT_FOUND");
 assert.equal(touched,false);
 assert.equal(count(db,"legacy_import_batches"),0);
});
