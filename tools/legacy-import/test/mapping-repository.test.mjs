import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { LegacyMappingRepository, MappingStoreError } from "../mapping-repository.mjs";
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
 // These are domain tables defined in the complete canonical v2 schema.
 // Stub their PKs to test the legacy section WITHOUT duplicating its DDL.
 for(const table of ["contents","content_sections","content_units","user_collections",
                     "user_collection_items","storage_objects"])
   db.exec("CREATE TABLE "+table+"(id TEXT PRIMARY KEY)");
 db.exec(authoritativeSql);
 return new LegacyMappingRepository(db);
}
const A="local.db", T="comics";
function key(datasetId,id="42") {
 return {datasetId,fileRole:A,tableKind:T,legacyTypeKey:"1",legacyId:id};
}
const DIGEST="1".repeat(64);
test("canonical v2 import tables execute as SQLite DDL", t=>{
 const db=setup(t);
 assert.ok(db);
});
test("dataset persisted with owner scope, no auto filename identity",t=>{
 const store=setup(t);
 const id=store.createDatasetForApprovedImport({ownerScopeId:"user-A",displayLabel:"old phone"});
 assert.equal(store.findDataset({ownerScopeId:"user-A",datasetId:id}).id,id);
 assert.equal(store.findDataset({ownerScopeId:"user-B",datasetId:id}),null);
});
test("record reimport idempotent and changed digest goes to pending review",t=>{
 const repo=setup(t);
 const ds=repo.createDatasetForApprovedImport({ownerScopeId:"user-A",displayLabel:"old phone"});
 const first=repo.reserveAfterApprovedPlan({ownerScopeId:"user-A",key:key(ds),recordDigest:DIGEST});
 assert.equal(first.state,"reserved_unresolved");
 const again=repo.reserveAfterApprovedPlan({ownerScopeId:"user-A",key:key(ds),recordDigest:DIGEST});
 assert.equal(again.state,"existing");
 assert.equal(first.mappingId,again.mappingId);
 const newer=repo.reserveAfterApprovedPlan({ownerScopeId:"user-A",key:key(ds),recordDigest:"2".repeat(64)});
 assert.equal(newer.state,"changed_pending");
 assert.equal(newer.mappingId,first.mappingId);
 assert.equal(repo.lookupMapping({ownerScopeId:"user-A",key:key(ds)}).source_record_digest,DIGEST);
});
test("cross-user injected scope never reserves or reads another dataset",t=>{
 const repo=setup(t);
 const ds=repo.createDatasetForApprovedImport({ownerScopeId:"user-A",displayLabel:"source"});
 assert.throws(()=>repo.reserveAfterApprovedPlan({
   ownerScopeId:"user-B",key:key(ds),recordDigest:DIGEST
 }),e=>e instanceof MappingStoreError && e.code==="LEGACY_MAPPING_SCOPE_DENIED");
 assert.equal(repo.lookupMapping({ownerScopeId:"user-B",key:key(ds)}),null);
});
test("different dataset same old numeric work ID remains distinct",t=>{
 const repo=setup(t);
 const d1=repo.createDatasetForApprovedImport({ownerScopeId:"user-A",displayLabel:"phone"});
 const d2=repo.createDatasetForApprovedImport({ownerScopeId:"user-A",displayLabel:"tablet"});
 const a=repo.reserveAfterApprovedPlan({ownerScopeId:"user-A",key:key(d1),recordDigest:DIGEST});
 const b=repo.reserveAfterApprovedPlan({ownerScopeId:"user-A",key:key(d2),recordDigest:DIGEST});
 assert.notEqual(a.mappingId,b.mappingId);
});
