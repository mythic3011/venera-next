import test from "node:test";
import assert from "node:assert/strict";
import { legacyRecordIdentity, newProvisionalDatasetId, LegacyIdentityError } from "../record-identity.mjs";

const ds = "62904ae0-9975-4a10-a5eb-5ff3051ebc9d";
function id(overrides={}) {
  return legacyRecordIdentity({
    datasetId: ds, fileRole: "local.db", tableKind: "comics",
    legacyTypeKey: "1", legacyId: "42", ...overrides,
  });
}
test("record ID is stable across changed metadata and file snapshots", () => {
  assert.equal(id().keyDigest,id().keyDigest);
  assert.equal(id().tuple.length,6);
  assert.notEqual(id().keyDigest,id({legacyId:"43"}).keyDigest);
});
test("same numeric old ID in separate old installations cannot collide", () => {
  assert.notEqual(id().keyDigest,
    id({datasetId:"36df0b6b-11cc-43d9-a17b-7a2ae0c4ad01"}).keyDigest);
  assert.match(newProvisionalDatasetId(), /^[0-9a-f-]{36}$/);
});
test("type, role and folder are explicit parts of record identity", () => {
  assert.notEqual(id({legacyTypeKey:"1"}).keyDigest,id({legacyTypeKey:"2"}).keyDigest);
  const a=legacyRecordIdentity({datasetId:ds,fileRole:"local_favorite.db",
    tableKind:"folder_item",scopeKey:"School",legacyTypeKey:"1",legacyId:"42"});
  const b=legacyRecordIdentity({datasetId:ds,fileRole:"local_favorite.db",
    tableKind:"folder_item",scopeKey:"Home",legacyTypeKey:"1",legacyId:"42"});
  assert.notEqual(a.keyDigest,b.keyDigest);
  const c=legacyRecordIdentity({datasetId:ds,fileRole:"history.db",
    tableKind:"image_favorites",legacyTypeKey:"ehentai",legacyId:"42"});
  assert.notEqual(a.keyDigest,c.keyDigest);
});
test("ambiguous separators never alias tuple components", () => {
  const a=id({legacyTypeKey:"a:b",legacyId:"c"});
  const b=id({legacyTypeKey:"a",legacyId:"b:c"});
  assert.notEqual(a.keyDigest,b.keyDigest);
});
test("file-role allowlist and type constraints are enforced", () => {
  for(const changes of [
    {fileRole:"venera.db"},
    {fileRole:"appdata.json",tableKind:"comics"},
    {legacyTypeKey:""},
    {legacyId:""},
    {legacyId:"\u0000"},
    {datasetId:"not-a-uuid"},
  ]) assert.throws(()=>id(changes), LegacyIdentityError);
  assert.throws(()=>legacyRecordIdentity({
    datasetId:ds,fileRole:"local_favorite.db",tableKind:"folder_item",
    scopeKey:"",legacyId:"1"
  }), LegacyIdentityError);
});
test("settings keys are separate; local identity is not canonical ContentId", () => {
  const one=legacyRecordIdentity({datasetId:ds,fileRole:"appdata.json",
    tableKind:"settings",legacyId:"theme_mode"});
  const two=legacyRecordIdentity({datasetId:ds,fileRole:"appdata.json",
    tableKind:"settings",legacyId:"language"});
  assert.notEqual(one.keyDigest,two.keyDigest);
  assert.match(one.keyDigest,/^[0-9a-f]{64}$/);
});
