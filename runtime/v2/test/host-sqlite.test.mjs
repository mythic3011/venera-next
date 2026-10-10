import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { bindTrustedFreshV2Sqlite,createTrustedInMemoryV2Runtime,
  V2RuntimeError } from "../src/host-sqlite.mjs";

const violation=(code)=>e=>e instanceof V2RuntimeError&&e.code===code;
const setup=async(t)=>{
  const host=await createTrustedInMemoryV2Runtime();
  t.after(()=>host.close());
  return host.runtime;
};
test("greenfield host boundary never leaks raw SQL or old runtime model",async t=>{
  const api=await setup(t);
  assert.deepEqual(Object.keys(api).sort(),[
    "addSectionDraft","clearReaderPosition","createContentDraft",
    "getReaderPosition","openSection","setActiveOrder","updateReaderPosition"
  ]);
  assert.equal("db" in api,false);
  assert.equal("executeSql" in api,false);
  assert.ok(Object.isFrozen(api));
});
test("create canonical draft normalizes title and permits duplicate lookup keys",async t=>{
  const api=await setup(t);
  const a=api.createContentDraft({title:"  SAME  TITLE  "});
  const b=api.createContentDraft({title:"same title"});
  assert.equal(a.title,"SAME TITLE");
  assert.notEqual(a.contentId,b.contentId);
  assert.equal(a.status,"metadata_only");
  assert.equal(api.getReaderPosition({contentId:a.contentId}),null);
  assert.throws(()=>api.createContentDraft({title:"  "}),violation("V2_INPUT_INVALID"));
  assert.throws(()=>api.createContentDraft({title:"OK",contentType:"pdf"}),
    violation("V2_CONTENT_TYPE_DEFERRED"));
});
test("reader position updates from verified same-content units and keeps lifecycle",async t=>{
  const api=await setup(t);
  const comic=api.createContentDraft({title:"One"});
  const chapter=api.addSectionDraft({contentId:comic.contentId,title:"Chapter 1",
    unitIndexes:[0,2,9]});
  const target=chapter.units[1].id;
  const first=api.updateReaderPosition({contentId:comic.contentId,unitId:target});
  assert.equal(first.status,"written");
  const state=api.getReaderPosition({contentId:comic.contentId});
  assert.equal(state.unitId,target);
  assert.equal(state.sectionId,chapter.sectionId);
  assert.equal(state.unitIndex,2);
  const repeat=api.updateReaderPosition({contentId:comic.contentId,unitId:target});
  assert.deepEqual(repeat,{sessionId:first.sessionId,status:"skipped_unchanged"});
  const next=api.updateReaderPosition({
    contentId:comic.contentId,unitId:chapter.units[2].id
  });
  assert.equal(next.sessionId,first.sessionId);
  assert.equal(next.status,"written");
  assert.equal(api.getReaderPosition({contentId:comic.contentId}).unitIndex,9);
  assert.equal(api.clearReaderPosition({contentId:comic.contentId}).status,"abandoned");
  assert.equal(api.getReaderPosition({contentId:comic.contentId}),null);
  assert.equal(api.clearReaderPosition({contentId:comic.contentId}).status,"no_active_session");
  const created=api.updateReaderPosition({contentId:comic.contentId,unitId:target});
  assert.notEqual(created.sessionId,first.sessionId);
});
test("cross-Content position is rejected and cannot mutate prior active session",async t=>{
  const api=await setup(t),a=api.createContentDraft({title:"A"}),
    b=api.createContentDraft({title:"B"});
  const unitA=api.addSectionDraft({contentId:a.contentId,unitIndexes:[0]});
  const unitB=api.addSectionDraft({contentId:b.contentId,unitIndexes:[0]});
  api.updateReaderPosition({contentId:a.contentId,unitId:unitA.units[0].id});
  const prior=api.getReaderPosition({contentId:a.contentId});
  assert.throws(()=>api.updateReaderPosition({
    contentId:a.contentId,unitId:unitB.units[0].id
  }),violation("V2_READER_INVALID_POSITION"));
  assert.deepEqual(api.getReaderPosition({contentId:a.contentId}),prior);
  assert.equal(api.getReaderPosition({contentId:b.contentId}),null);
  assert.throws(()=>api.updateReaderPosition({
    contentId:a.contentId,unitId:unitA.units[0].id,
    sourceLinkId:"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
  }),violation("V2_READER_INVALID_SOURCE"));
});
test("source fallback uses unit_index; complete active override uses explicit order",async t=>{
 const api=await setup(t),a=api.createContentDraft({title:"Index"});
 const section=api.addSectionDraft({
   contentId:a.contentId,unitIndexes:[3,0,12,1]
 });
 const fallback=api.openSection({contentId:a.contentId,sectionId:section.sectionId});
 assert.equal(fallback.orderType,"source_fallback");
 assert.deepEqual(fallback.units.map(x=>x.unit_index),[0,1,3,12]);
 assert.ok(fallback.units.every(x=>x.assetStatus==="unavailable"));
 const reversed=[...fallback.units.map(x=>x.id)].reverse();
 const result=api.setActiveOrder({
   contentId:a.contentId,sectionId:section.sectionId,unitIds:reversed
 });
 assert.equal(result.unitIds.length,4);
 const active=api.openSection({contentId:a.contentId,sectionId:section.sectionId});
 assert.equal(active.orderType,"active");
 assert.deepEqual(active.units.map(x=>x.id),reversed);
 const alternate=[...reversed].reverse();
 api.setActiveOrder({contentId:a.contentId,sectionId:section.sectionId,
   unitIds:alternate});
 assert.deepEqual(api.openSection({contentId:a.contentId,
   sectionId:section.sectionId}).units.map(x=>x.id),alternate);
});
test("incomplete or foreign active unit order never falls back silently",async t=>{
 const api=await setup(t),a=api.createContentDraft({title:"A"}),
   b=api.createContentDraft({title:"B"});
 const sect=api.addSectionDraft({contentId:a.contentId,unitIndexes:[0,1,2]});
 const other=api.addSectionDraft({contentId:b.contentId,unitIndexes:[0]});
 const initial=api.openSection({contentId:a.contentId,sectionId:sect.sectionId});
 for(const list of [
   [sect.units[0].id],
   [sect.units[0].id,sect.units[1].id,other.units[0].id],
   [sect.units[0].id,sect.units[0].id,sect.units[1].id]
 ])assert.throws(()=>api.setActiveOrder({
   contentId:a.contentId,sectionId:sect.sectionId,unitIds:list
 }),e=>e instanceof V2RuntimeError&&
   ["V2_ORDER_INCOMPLETE","V2_ORDER_INVALID"].includes(e.code));
 assert.deepEqual(api.openSection({contentId:a.contentId,sectionId:sect.sectionId}),initial);
});
test("metadata only draft and unit indexes must reject arbitrary legacy payloads",async t=>{
 const api=await setup(t),a=api.createContentDraft({title:"Valid"});
 for(const indexes of [[-1],[1.1],[0,0],[],["1"],null])
   assert.throws(()=>api.addSectionDraft({
     contentId:a.contentId,title:"Safe",unitIndexes:indexes
   }),violation("V2_UNIT_INDEX_INVALID"));
 assert.throws(()=>api.addSectionDraft({
   contentId:"legacy-id-42",unitIndexes:[0]
 }),violation("V2_ID_INVALID"));
 assert.throws(()=>api.openSection({contentId:a.contentId,
   sectionId:"11111111-1111-4111-8111-111111111111"}),violation("V2_SECTION_NOT_FOUND"));
});
test("host adapter fails closed on old physical runtime tables or foreign keys disabled",()=>{
 const db=new DatabaseSync(":memory:");
 try{
   db.exec("CREATE TABLE comics(id TEXT)");
   assert.throws(()=>bindTrustedFreshV2Sqlite(db),violation("V2_SCHEMA_REQUIRED"));
 }finally{db.close();}
});
