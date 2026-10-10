// Fresh-v2 design-authoritative SQLite foundation. No discarded runtime,
// old data, compatibility migration or old plugin code is executed.
import { readFile } from "node:fs/promises";

export class FreshSchemaError extends Error {
  constructor(code){ super(code); this.name="FreshSchemaError"; this.code=code; }
}
const deny=code=>{ throw new FreshSchemaError(code); };
export const V2_CORE_HEADINGS=Object.freeze([
 "contents","content_metadata","content_titles","content_sections",
 "content_units","source_platforms","source_links","section_source_links",
 "content_unit_orders","content_unit_order_items","reading_sessions",
 "storage_backends","storage_objects","storage_placements",
]);
export const V2_COLLECTION_HEADINGS=Object.freeze([
 "user_collections","user_collection_items"
]);
export const LEGACY_IMPORT_HEADING="One-Time Legacy Distributed Import Tables (canonical schema authority)";
const EXPECTED_LEGACY_TABLES=Object.freeze([
 "legacy_import_datasets","legacy_import_batches","legacy_record_mappings",
 "legacy_unresolved_records","legacy_asset_journal","legacy_import_receipts"
]);
const DISCARDED_TABLES=Object.freeze(["comics","chapters","pages","reader_sessions",
  "page_orders","page_order_items","chapter_source_links","comic_metadata"]);
function fencedSection(markdown,heading,fence) {
  const lines=markdown.split(/\r?\n/);
  // Canonical design headings may include a human explanatory suffix
  // e.g. "(replaces comics)". Match exact table name plus only that suffix.
  const accepts=x=>x===heading || x.startsWith(heading+" (replaces ");
  const matching=lines.map((x,i)=>accepts(x)?i:-1).filter(i=>i>=0);
  if(matching.length!==1)deny("FRESH_SCHEMA_SECTION_MISSING");
  const h=matching[0];
  const begin=lines.findIndex((x,i)=>i>h && x===fence);
  if(begin<0 || lines.slice(h+1,begin).some(x=>x.startsWith("## ")))
    deny("FRESH_SCHEMA_FENCE_MISSING");
  const finish=lines.findIndex((x,i)=>i>begin &&
    x===(fence.startsWith("~~~")?"~~~":"\x60\x60\x60"));
  if(finish<0 || lines.slice(begin+1,finish).some(x=>x.startsWith("## ")))
    deny("FRESH_SCHEMA_FENCE_MISSING");
  const body=lines.slice(begin+1,finish).join("\n").trim();
  if(!body.startsWith("CREATE TABLE ") || body.length>50000)
    deny("FRESH_SCHEMA_INVALID_SECTION");
  return body;
}
export function extractFreshV2Sql(markdown) {
  if(typeof markdown!=="string" || markdown.length<100)
    deny("FRESH_SCHEMA_SOURCE_INVALID");
  const sections=[
    ...V2_CORE_HEADINGS.map(s=>fencedSection(markdown,"## "+s,"\x60\x60\x60sql")),
    // Collection tables are FK targets for L0 evidence only; M2 workflows
    // are NOT enabled by this physical schema presence.
    ...V2_COLLECTION_HEADINGS.map(s=>fencedSection(markdown,"## "+s,"\x60\x60\x60sql")),
    fencedSection(markdown,"## "+LEGACY_IMPORT_HEADING,"~~~sql")
  ];
  const wire=sections.join("\n");
  for(const table of [...V2_CORE_HEADINGS,...V2_COLLECTION_HEADINGS,
                        ...EXPECTED_LEGACY_TABLES]) {
    const found=wire.match(new RegExp("\\bCREATE TABLE "+table+"\\s*\\(","g"))??[];
    if(found.length!==1)deny("FRESH_SCHEMA_TABLE_MISMATCH");
  }
  for(const old of DISCARDED_TABLES)
    if(new RegExp("\\bCREATE TABLE "+old+"\\s*\\(").test(wire))
      deny("FRESH_SCHEMA_LEGACY_TABLE");
  return sections;
}
function currentTables(db) {
  return db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").all().map(x=>x.name);
}
export function initializeFreshV2Database(db,sections) {
  if(!db || typeof db.exec!=="function" || typeof db.prepare!=="function" ||
     !Array.isArray(sections) || sections.length!==V2_CORE_HEADINGS.length+
       V2_COLLECTION_HEADINGS.length+1 ||
     sections.some(s=>typeof s!=="string" || !s.startsWith("CREATE TABLE ")))
    deny("FRESH_SCHEMA_INVALID_INSTALL");
  if(currentTables(db).length)deny("FRESH_SCHEMA_TARGET_NOT_EMPTY");
  db.exec("PRAGMA foreign_keys=ON");
  db.exec("BEGIN IMMEDIATE");
  try{
    for(const body of sections)db.exec(body);
    const names=new Set(currentTables(db));
    for(const name of [...V2_CORE_HEADINGS,...V2_COLLECTION_HEADINGS,
                        ...EXPECTED_LEGACY_TABLES])
      if(!names.has(name))deny("FRESH_SCHEMA_TABLE_MISMATCH");
    const fk=db.prepare("PRAGMA foreign_key_check").all();
    if(fk.length)deny("FRESH_SCHEMA_FOREIGN_KEY_FAILURE");
    db.exec("COMMIT");
    return Object.freeze({schemaFamily:"fresh-v2-content-unit",
      legacyImportScope:"five-file-only",tables:names.size,canImportContent:false});
  }catch(e){
    db.exec("ROLLBACK");
    if(e instanceof FreshSchemaError)throw e;
    deny("FRESH_SCHEMA_INSTALL_FAILED");
  }
}
export async function loadReviewedFreshV2Sql({
  designPath=new URL("../../docs/design/v2/02_DATABASE_SCHEMA.md",import.meta.url)
}={}){
  return extractFreshV2Sql(await readFile(designPath,"utf8"));
}
