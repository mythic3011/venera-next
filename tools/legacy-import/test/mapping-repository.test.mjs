import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { LegacyMappingRepository, MappingStoreError } from "../mapping-repository.mjs";
import { makeTrustedPreviewPlan, TrustedLegacyApprovalService, LegacyApprovalError } from "../approval-gate.mjs";

const DOC=new URL("../../../docs/design/v2/02_DATABASE_SCHEMA.md",import.meta.url);
const schema=readFileSync(DOC,"utf8");
const start=schema.indexOf("CREATE TABLE legacy_import_datasets (");
const end=schema.indexOf("~~~",start);
assert.ok(start>=0 && end>start,"canonical v2 SQL section is present");
const authoritativeSql=schema.slice(start,end);

function setup(t) {
  const db=new DatabaseSync(":memory:");
  t.after(()=>db.close());
  db.exec("PRAGMA foreign_keys=ON");
  // Canonical v2 FK target placeholders, not replacement production schema.
  for(const table of ["contents","content_sections","content_units","user_collections",
                       "user_collection_items","storage_objects"])
    db.exec("CREATE TABLE "+table+"(id TEXT PRIMARY KEY)");
  db.exec(authoritativeSql);
  return new LegacyMappingRepository(db);
}
const DIGEST="1".repeat(64);
const SHA2="2".repeat(64);
const SHA3="3".repeat(64);
const A="local.db", T="comics";
function key(datasetId,id="42",changes={}) {
  return {datasetId,fileRole:A,tableKind:T,legacyTypeKey:"1",legacyId:id,...changes};
}
function plan(ownerScopeId,datasetId,options={}) {
  return makeTrustedPreviewPlan({
    ownerScopeId,datasetId,policyRevision:"v1",
    inputManifest:options.inputManifest || [{role:"local.db",sha256:DIGEST}]
  });
}
async function approve(repo,ownerScopeId,datasetId,changes={}) {
  const p=plan(ownerScopeId,datasetId,changes);
  const gate=new TrustedLegacyApprovalService({
    canonicalDb:repo.db,
    // The following callbacks are test-only stubs! Product host must verify
    // one real trusted UI gesture and matching immutable input snapshots.
    verifyTrustedUserGesture: changes.gestureCheck || (async ()=>true),
    verifyCurrentSnapshots: changes.snapshotCheck || (async ()=>true),
  });
  const approved=await gate.approve({plan:p,gesture:{mock:true},expectedPlanDigest:p.planDigest});
  return {batchId:approved.batchId,expectedPlanDigest:approved.planDigest};
}
function reserve(repo,ownerScopeId,datasetId,approval,extra={}) {
  return repo.reserveAfterApprovedPlan({
    ownerScopeId,...approval,key:key(datasetId),recordDigest:DIGEST,...extra
  });
}
function count(repo,table) {
  return repo.db.prepare("SELECT COUNT(*) AS n FROM "+table).get().n;
}

test("fresh-v2 six-table DDL executes with FK enforcement", t=>{
  const repo=setup(t);
  assert.equal(count(repo,"legacy_import_batches"),0);
  assert.equal(count(repo,"legacy_record_mappings"),0);
});
test("dataset is scoped to owner; generating a preview plan is read-only",t=>{
  const repo=setup(t);
  const id=repo.createDatasetForApprovedImport({ownerScopeId:"user-A",displayLabel:"old phone"});
  const original=count(repo,"legacy_import_batches");
  const proposed=plan("user-A",id);
  assert.match(proposed.planDigest,/^[a-f0-9]{64}$/);
  assert.equal(count(repo,"legacy_import_batches"),original);
  assert.equal(repo.findDataset({ownerScopeId:"user-A",datasetId:id}).id,id);
  assert.equal(repo.findDataset({ownerScopeId:"user-B",datasetId:id}),null);
});
test("missing approval denies mapping reservation BEFORE insert", t=>{
  const repo=setup(t);
  const ds=repo.createDatasetForApprovedImport({ownerScopeId:"user-A",displayLabel:"phone"});
  assert.throws(()=>reserve(repo,"user-A",ds,{}),
    e=>e instanceof MappingStoreError && e.code==="LEGACY_APPROVAL_REQUIRED");
  assert.equal(count(repo,"legacy_record_mappings"),0);
});
test("approved batch binds exact digest and owner; reimport is idempotent",async t=>{
  const repo=setup(t);
  const ds=repo.createDatasetForApprovedImport({ownerScopeId:"user-A",displayLabel:"old phone"});
  const a=await approve(repo,"user-A",ds);
  const first=reserve(repo,"user-A",ds,a);
  assert.equal(first.state,"reserved_unresolved");
  const again=reserve(repo,"user-A",ds,a);
  assert.equal(again.state,"existing");
  assert.equal(first.mappingId,again.mappingId);
  const newer=reserve(repo,"user-A",ds,a,{recordDigest:SHA2});
  assert.equal(newer.state,"changed_pending");
  assert.equal(newer.mappingId,first.mappingId);
  const stored=repo.lookupMapping({ownerScopeId:"user-A",key:key(ds)});
  assert.equal(stored.source_record_digest,DIGEST);
  assert.equal(count(repo,"legacy_record_mappings"),1);
});
test("forged batch, altered digest, cross-owner and revoked state deny",async t=>{
  const repo=setup(t);
  const ds=repo.createDatasetForApprovedImport({ownerScopeId:"user-A",displayLabel:"phone"});
  const batch=await approve(repo,"user-A",ds);
  for(const changes of [
    {batchId:"00000000-0000-4000-8000-000000000000"},
    {expectedPlanDigest:SHA3},
    {ownerScopeId:"user-B"},
  ]) {
    assert.throws(()=>reserve(repo,"user-A",ds,batch,changes),MappingStoreError);
  }
  repo.db.prepare("UPDATE legacy_import_batches SET state='cancelled', completed_at=? WHERE id=?")
    .run(new Date().toISOString(),batch.batchId);
  assert.throws(()=>reserve(repo,"user-A",ds,batch),
    e=>e instanceof MappingStoreError && e.code==="LEGACY_APPROVAL_REQUIRED");
  assert.equal(count(repo,"legacy_record_mappings"),0);
});
test("approved manifest cannot be used for a different file role",async t=>{
  const repo=setup(t);
  const ds=repo.createDatasetForApprovedImport({ownerScopeId:"user-A",displayLabel:"phone"});
  const batch=await approve(repo,"user-A",ds);
  assert.throws(()=>reserve(repo,"user-A",ds,batch,{
    key:key(ds,"42",{fileRole:"history.db",tableKind:"history"})
  }),e=>e instanceof MappingStoreError&&e.code==="LEGACY_APPROVAL_ROLE_DENIED");
  assert.equal(count(repo,"legacy_record_mappings"),0);
});
test("gesture denial and changed snapshot cannot persist approval",async t=>{
  const repo=setup(t);
  const ds=repo.createDatasetForApprovedImport({ownerScopeId:"user-A",displayLabel:"phone"});
  await assert.rejects(approve(repo,"user-A",ds,{gestureCheck:async()=>false}),
    e=>e instanceof LegacyApprovalError&&e.code==="LEGACY_APPROVAL_GESTURE_REJECTED");
  await assert.rejects(approve(repo,"user-A",ds,{snapshotCheck:async()=>false}),
    e=>e instanceof LegacyApprovalError&&e.code==="LEGACY_APPROVAL_STALE");
  assert.equal(count(repo,"legacy_import_batches"),0);
});
test("user-approved digest must match full trusted preview plan",async t=>{
  const repo=setup(t);
  const ds=repo.createDatasetForApprovedImport({ownerScopeId:"user-A",displayLabel:"phone"});
  const p=plan("user-A",ds);
  const gate=new TrustedLegacyApprovalService({
    canonicalDb:repo.db,verifyTrustedUserGesture:async()=>true,
    verifyCurrentSnapshots:async()=>true
  });
  await assert.rejects(gate.approve({plan:p,gesture:{mock:true},expectedPlanDigest:SHA3}),
    e=>e instanceof LegacyApprovalError&&e.code==="LEGACY_APPROVAL_PLAN_MISMATCH");
  assert.equal(count(repo,"legacy_import_batches"),0);
});
test("malformed/duplicate/unknown input roles are rejected before DB", t=>{
  const repo=setup(t);
  const ds=repo.createDatasetForApprovedImport({ownerScopeId:"user-A",displayLabel:"phone"});
  for(const manifest of [
    [{role:"venera.db",sha256:DIGEST}],
    [{role:"local.db",sha256:DIGEST},{role:"local.db",sha256:SHA2}],
    [{role:"local.db",sha256:"bad"}],
    [{role:"local.db",sha256:DIGEST,path:"secret"}],
    [],
  ]) {
    assert.throws(()=>plan("user-A",ds,{inputManifest:manifest}),LegacyApprovalError);
  }
  assert.equal(count(repo,"legacy_import_batches"),0);
});
test("dataset owner mismatch denies approval even when gesture mock passes",async t=>{
  const repo=setup(t);
  const ds=repo.createDatasetForApprovedImport({ownerScopeId:"user-A",displayLabel:"phone"});
  await assert.rejects(approve(repo,"user-B",ds),
    e=>e instanceof LegacyApprovalError&&e.code==="LEGACY_APPROVAL_DATASET_DENIED");
  assert.equal(count(repo,"legacy_import_batches"),0);
});
test("two datasets with same old numeric ID never collide",async t=>{
  const repo=setup(t);
  const d1=repo.createDatasetForApprovedImport({ownerScopeId:"user-A",displayLabel:"phone"});
  const d2=repo.createDatasetForApprovedImport({ownerScopeId:"user-A",displayLabel:"tablet"});
  const a=await approve(repo,"user-A",d1);
  const b=await approve(repo,"user-A",d2);
  const first=reserve(repo,"user-A",d1,a), second=reserve(repo,"user-A",d2,b);
  assert.notEqual(first.mappingId,second.mappingId);
});
