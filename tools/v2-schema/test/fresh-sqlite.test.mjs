import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { DatabaseSync } from "node:sqlite";
import { extractFreshV2Sql, initializeFreshV2Database, loadReviewedFreshV2Sql,
  FreshSchemaError } from "../fresh-sqlite.mjs";

const OLD=["comics","chapters","pages","reader_sessions","comic_metadata"];
function fresh(t) {
  const db=new DatabaseSync(":memory:");
  t.after(()=>db.close());
  return db;
}
const stmt=(db,s)=>db.prepare(s).all();
test("extracts fresh canonical tables from checked-in design authority",async t=>{
  const sql=await loadReviewedFreshV2Sql();
  const db=fresh(t);
  const result=initializeFreshV2Database(db,sql);
  assert.equal(result.schemaFamily,"fresh-v2-content-unit");
  assert.equal(result.canImportContent,false);
  const tables=new Set(stmt(db,"SELECT name FROM sqlite_master WHERE type='table'").map(x=>x.name));
  for(const table of ["contents","content_sections","content_units","reading_sessions",
     "content_unit_orders","legacy_import_datasets","legacy_record_mappings",
     "legacy_asset_journal","user_collections"])assert.ok(tables.has(table),table);
  for(const table of OLD)assert.ok(!tables.has(table),"discarded table leaked: "+table);
  assert.equal(stmt(db,"PRAGMA foreign_key_check").length,0);
});
test("fresh schema is empty-only, never migrates/disguises old runtime database",async t=>{
  const sql=await loadReviewedFreshV2Sql();
  const db=fresh(t);
  db.exec("CREATE TABLE comics(id TEXT PRIMARY KEY)");
  assert.throws(()=>initializeFreshV2Database(db,sql),
    e=>e instanceof FreshSchemaError&&e.code==="FRESH_SCHEMA_TARGET_NOT_EMPTY");
  assert.deepEqual(stmt(db,"SELECT name FROM sqlite_master WHERE type='table'").map(x=>x.name),
    ["comics"]);
});
test("bootstrap rollback restores empty target after bad SQL fragment",async t=>{
  const sections=await loadReviewedFreshV2Sql();
  const broken=sections.slice();
  broken[3]="CREATE TABLE broken (";
  const db=fresh(t);
  assert.throws(()=>initializeFreshV2Database(db,broken),
    e=>e instanceof FreshSchemaError&&e.code==="FRESH_SCHEMA_INSTALL_FAILED");
  assert.equal(stmt(db,"SELECT name FROM sqlite_master WHERE type='table'").length,0);
});
test("changed, duplicated or missing schema section fails closed",async()=>{
  const source=await readFile(new URL("../../../docs/design/v2/02_DATABASE_SCHEMA.md",
    import.meta.url),"utf8");
  for(const text of [
    source.replace("## content_units (replaces pages)","## lost_units"),
    source.replace("CREATE TABLE contents (","CREATE TABLE comics ("),
    source+"\n## contents\n"
  ])assert.throws(()=>extractFreshV2Sql(text),FreshSchemaError);
});
test("one-active-session and one-active-order constraints use fresh ContentUnit authority",async t=>{
  const db=fresh(t);
  initializeFreshV2Database(db,await loadReviewedFreshV2Sql());
  const now="2026-10-10T00:00:00Z";
  db.prepare("INSERT INTO contents(id,content_type,normalized_title,created_at,updated_at) VALUES (?,?,?,?,?)")
    .run("content1","comic","title",now,now);
  db.prepare("INSERT INTO content_sections(id,content_id,section_kind,created_at,updated_at) VALUES (?,?,?,?,?)")
    .run("section1","content1","chapter",now,now);
  db.prepare("INSERT INTO content_units(id,section_id,unit_index,unit_type,created_at,updated_at) VALUES (?,?,?,?,?,?)")
    .run("unit1","section1",0,"image",now,now);
  db.prepare("INSERT INTO reading_sessions(id,content_id,unit_id,session_state,created_at,updated_at) VALUES (?,?,?,?,?,?)")
    .run("s1","content1","unit1","active",now,now);
  assert.throws(()=>db.prepare(
    "INSERT INTO reading_sessions(id,content_id,unit_id,session_state,created_at,updated_at) VALUES (?,?,?,?,?,?)"
  ).run("s2","content1","unit1","active",now,now),/UNIQUE constraint failed/);
  db.prepare("INSERT INTO content_unit_orders(id,section_id,order_type,status,created_at,updated_at) VALUES (?,?,?,?,?,?)")
    .run("o1","section1","source","active",now,now);
  assert.throws(()=>db.prepare(
    "INSERT INTO content_unit_orders(id,section_id,order_type,status,created_at,updated_at) VALUES (?,?,?,?,?,?)"
  ).run("o2","section1","source","active",now,now),/UNIQUE constraint failed/);
  assert.equal(stmt(db,"PRAGMA foreign_key_check").length,0);
});
test("evidence-only and plan-only CHECK scopes remain enforced by fresh schema",async t=>{
 const db=fresh(t);
 initializeFreshV2Database(db,await loadReviewedFreshV2Sql());
 const now="2026-10-10T00:00:00Z";
 db.prepare("INSERT INTO legacy_import_datasets(id,owner_scope_id,display_label,state,created_at,updated_at) VALUES(?,?,?,?,?,?)")
   .run("ds1","owner","old","active",now,now);
 assert.throws(()=>db.prepare(
   "INSERT INTO legacy_import_batches(id,dataset_id,input_manifest_json,policy_revision,plan_digest,approval_scope,state,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)"
 ).run("batch1","ds1","[]","v1","a".repeat(64),"content_import","selected",now,now),/CHECK constraint failed/);
});
