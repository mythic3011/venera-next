// Greenfield v2 host SQLite adapter — NO imports from discarded runtime/core.
// This is a canonical metadata/reader persistence spine, NOT an asset importer.
// The DB handle must be owned by the trusted native host.
import { randomUUID } from "node:crypto";
import { DatabaseSync } from "node:sqlite";
import { initializeFreshV2Database, loadReviewedFreshV2Sql } from
  "./schema-bootstrap.mjs";

export class V2RuntimeError extends Error {
  constructor(code){ super(code); this.name="V2RuntimeError"; this.code=code; }
}
const fail=code=>{ throw new V2RuntimeError(code); };
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const REQUIRED=["contents","content_metadata","content_titles","content_sections",
 "content_units","content_unit_orders","content_unit_order_items","reading_sessions",
 "storage_objects","storage_placements"];
const FORBIDDEN=["comics","chapters","pages","reader_sessions","page_orders","comic_metadata"];
function text(v,max=1024) {
  if(typeof v!=="string")fail("V2_INPUT_INVALID");
  const normalized=v.replace(/\s+/gu," ").trim();
  if(!normalized || normalized.length>max || normalized.includes("\0"))fail("V2_INPUT_INVALID");
  return normalized;
}
function id(v){if(typeof v!=="string"||!uuid.test(v))fail("V2_ID_INVALID");return v;}
function clock(){return new Date().toISOString();}
function transact(db,fn){
  db.exec("BEGIN IMMEDIATE");
  try {
    const value=fn();
    db.exec("COMMIT");
    return value;
  }catch(e){db.exec("ROLLBACK");throw e;}
}
function verifySchema(db) {
  const tables=new Set(db.prepare(
    "SELECT name FROM sqlite_master WHERE type='table'"
  ).all().map(x=>x.name));
  if(REQUIRED.some(x=>!tables.has(x)) || FORBIDDEN.some(x=>tables.has(x)))
    fail("V2_SCHEMA_REQUIRED");
  if(db.prepare("PRAGMA foreign_key_check").all().length)
    fail("V2_FOREIGN_KEY_INVALID");
  // Live host handle must actually enforce FKs. Setting it in a transaction
  // would silently fail; require this before any caller can write.
  if(db.prepare("PRAGMA foreign_keys").get().foreign_keys!==1)
    fail("V2_FOREIGN_KEYS_OFF");
  const fields={
    contents:["content_type","normalized_title","library_status"],
    content_metadata:["content_id","title"],
    content_titles:["content_id","title_kind","normalized_title"],
    content_sections:["content_id","section_kind"],
    content_units:["section_id","unit_index","unit_type","storage_object_id"],
    content_unit_orders:["section_id","status"],
    content_unit_order_items:["order_id","unit_id","sort_index"],
    reading_sessions:["content_id","unit_id","session_state"]
  };
  for(const [table,expected] of Object.entries(fields)){
    const names=new Set(db.prepare("PRAGMA table_info("+table+")").all().map(x=>x.name));
    if(expected.some(name=>!names.has(name)))fail("V2_SCHEMA_REQUIRED");
  }
  for(const [table,name] of [
    ["reading_sessions","ux_reading_sessions_one_active"],
    ["content_unit_orders","ux_unit_orders_one_active"],
    ["content_unit_order_items","sqlite_autoindex_content_unit_order_items_1"]
  ]){
    const indexes=db.prepare("PRAGMA index_list("+table+")").all();
    if(!indexes.some(x=>x.name===name && x.unique===1))
      fail("V2_SCHEMA_REQUIRED");
  }
}
function assertContent(db,contentId) {
  const row=db.prepare("SELECT id FROM contents WHERE id=? AND library_status='active'")
    .get(id(contentId));
  if(!row)fail("V2_CONTENT_NOT_FOUND");
}
function unitsForSection(db,sectionId){
  return db.prepare(
    "SELECT u.id,u.unit_index,u.unit_type,u.storage_object_id "+
    "FROM content_units u WHERE u.section_id=? ORDER BY u.unit_index ASC,u.id ASC"
  ).all(id(sectionId));
}
function ordered(db,contentId,sectionId) {
  const section=db.prepare("SELECT id,content_id FROM content_sections WHERE id=?")
    .get(id(sectionId));
  if(!section || section.content_id!==id(contentId))fail("V2_SECTION_NOT_FOUND");
  const units=unitsForSection(db,sectionId);
  const order=db.prepare(
    "SELECT id FROM content_unit_orders WHERE section_id=? AND status='active'"
  ).get(sectionId);
  if(!order)return {orderType:"source_fallback",units};
  const rows=db.prepare(
    "SELECT oi.unit_id,oi.sort_index,u.section_id,u.unit_index,u.unit_type,u.storage_object_id "+
    "FROM content_unit_order_items oi LEFT JOIN content_units u ON u.id=oi.unit_id "+
    "WHERE oi.order_id=? ORDER BY oi.sort_index ASC"
  ).all(order.id);
  const expected=new Set(units.map(u=>u.id)),seen=new Set();
  if(rows.length!==units.length ||
     rows.some(r=>r.section_id!==sectionId || !expected.has(r.unit_id) ||
       seen.has(r.unit_id) || (seen.add(r.unit_id),false)) ||
     seen.size!==expected.size)fail("V2_INCOMPLETE_ACTIVE_ORDER");
  return {orderType:"active",units:rows.map(r=>({
    id:r.unit_id,unit_index:r.unit_index,unit_type:r.unit_type,
    storage_object_id:r.storage_object_id
  }))};
}
export function bindTrustedFreshV2Sqlite(db) {
  if(!db || typeof db.prepare!=="function" || typeof db.exec!=="function")
    fail("V2_HOST_DB_REQUIRED");
  verifySchema(db);
  const api={
    // A library metadata draft is NOT an imported readable work.
    createContentDraft({title,contentType="comic"}={}){
      const display=text(title);
      if(contentType!=="comic")fail("V2_CONTENT_TYPE_DEFERRED");
      const normalized=display.toLocaleLowerCase("und");
      const contentId=randomUUID(),titleId=randomUUID(),at=clock();
      transact(db,()=>{
        db.prepare("INSERT INTO contents (id,content_type,normalized_title,origin_hint,created_at,updated_at) VALUES (?,?,?,'local',?,?)")
          .run(contentId,"comic",normalized,at,at);
        db.prepare("INSERT INTO content_metadata (content_id,title,created_at,updated_at) VALUES (?,?,?,?)")
          .run(contentId,display,at,at);
        db.prepare("INSERT INTO content_titles (id,content_id,title,normalized_title,title_kind,created_at) VALUES (?,?,?,?,'primary',?)")
          .run(titleId,contentId,display,normalized,at);
      });
      return Object.freeze({contentId,title:display,titleId,status:"metadata_only"});
    },
    // Creates NO file byte/storage claim. This only tests the canonical
    // Section/Unit identity and ordering boundaries with metadata fixtures.
    addSectionDraft({contentId,title="Untitled Section",unitIndexes}={}){
      id(contentId);
      const label=text(title);
      if(!Array.isArray(unitIndexes) || unitIndexes.length<1 ||
         unitIndexes.length>10000 || unitIndexes.some(x=>!Number.isSafeInteger(x)||x<0) ||
         new Set(unitIndexes).size!==unitIndexes.length)
        fail("V2_UNIT_INDEX_INVALID");
      const sectionId=randomUUID(),at=clock();
      const units=unitIndexes.map(index=>({id:randomUUID(),unitIndex:index}));
      transact(db,()=>{
        assertContent(db,contentId);
        db.prepare("INSERT INTO content_sections (id,content_id,section_kind,title,display_label,created_at,updated_at) VALUES (?,?,'chapter',?,?,?,?)")
          .run(sectionId,contentId,label,label,at,at);
        const insert=db.prepare("INSERT INTO content_units (id,section_id,unit_index,unit_type,created_at,updated_at) VALUES (?,?,?,'image',?,?)");
        for(const unit of units)insert.run(unit.id,sectionId,unit.unitIndex,at,at);
      });
      return Object.freeze({sectionId,units:Object.freeze(units.map(x=>Object.freeze(x))),
        storageReady:false});
    },
    setActiveOrder({contentId,sectionId,unitIds}={}){
      id(contentId);id(sectionId);
      if(!Array.isArray(unitIds)||!unitIds.length||
         unitIds.length>10000 || unitIds.some(x=>!uuid.test(x)) ||
         new Set(unitIds).size!==unitIds.length)fail("V2_ORDER_INVALID");
      const at=clock(),newId=randomUUID();
      return transact(db,()=>{
        assertContent(db,contentId);
        const current=unitsForSection(db,sectionId);
        const requested=new Set(unitIds);
        const section=db.prepare(
          "SELECT id FROM content_sections WHERE id=? AND content_id=?"
        ).get(sectionId,contentId);
        if(!section || current.length!==unitIds.length ||
           current.some(x=>!requested.has(x.id)))
          fail("V2_ORDER_INCOMPLETE");
        db.prepare("UPDATE content_unit_orders SET status='superseded',updated_at=? WHERE section_id=? AND status='active'")
          .run(at,sectionId);
        db.prepare("INSERT INTO content_unit_orders (id,section_id,order_type,status,created_at,updated_at) VALUES (?,?,'user_override','active',?,?)")
          .run(newId,sectionId,at,at);
        const insert=db.prepare(
          "INSERT INTO content_unit_order_items (id,order_id,unit_id,sort_index,created_at) VALUES (?,?,?,?,?)"
        );
        unitIds.forEach((unitId,i)=>insert.run(randomUUID(),newId,unitId,i,at));
        ordered(db,contentId,sectionId); // ensure complete before DB commit
        return Object.freeze({orderId:newId,unitIds:Object.freeze([...unitIds])});
      });
    },
    openSection({contentId,sectionId}={}){
      id(contentId);id(sectionId);
      assertContent(db,contentId);
      const result=ordered(db,contentId,sectionId);
      return Object.freeze({...result,units:Object.freeze(result.units.map(u=>
        Object.freeze({...u,assetStatus:"unavailable"})))});
    },
    updateReaderPosition({contentId,unitId,sourceLinkId=null}={}){
      id(contentId);id(unitId);
      if(sourceLinkId!==null)id(sourceLinkId);
      return transact(db,()=>{
        assertContent(db,contentId);
        const target=db.prepare(
          "SELECT u.id,u.section_id FROM content_units u "+
          "JOIN content_sections s ON s.id=u.section_id "+
          "WHERE u.id=? AND s.content_id=?"
        ).get(unitId,contentId);
        if(!target)fail("V2_READER_INVALID_POSITION");
        if(!ordered(db,contentId,target.section_id).units.some(x=>x.id===unitId))
          fail("V2_READER_INVALID_POSITION");
        if(sourceLinkId!==null){
          const source=db.prepare("SELECT id FROM source_links WHERE id=? AND content_id=?")
            .get(sourceLinkId,contentId);
          if(!source)fail("V2_READER_INVALID_SOURCE");
        }
        const previous=db.prepare("SELECT * FROM reading_sessions WHERE content_id=? AND session_state='active'")
          .get(contentId);
        if(previous && previous.unit_id===unitId &&
           previous.source_link_id===sourceLinkId)
          return Object.freeze({sessionId:previous.id,status:"skipped_unchanged"});
        const at=clock();
        if(previous){
          db.prepare("UPDATE reading_sessions SET unit_id=?,source_link_id=?,updated_at=? WHERE id=?")
            .run(unitId,sourceLinkId,at,previous.id);
          return Object.freeze({sessionId:previous.id,status:"written"});
        }
        const sessionId=randomUUID();
        db.prepare("INSERT INTO reading_sessions (id,content_id,unit_id,source_link_id,session_state,created_at,updated_at) VALUES (?,?,?,?,'active',?,?)")
          .run(sessionId,contentId,unitId,sourceLinkId,at,at);
        return Object.freeze({sessionId,status:"written"});
      });
    },
    getReaderPosition({contentId}={}){
      id(contentId);assertContent(db,contentId);
      const row=db.prepare(
        "SELECT rs.id,rs.unit_id,rs.source_link_id,rs.updated_at,cu.section_id,cu.unit_index "+
        "FROM reading_sessions rs JOIN content_units cu ON cu.id=rs.unit_id "+
        "WHERE rs.content_id=? AND rs.session_state='active'"
      ).get(contentId);
      return row?Object.freeze({sessionId:row.id,unitId:row.unit_id,
        sourceLinkId:row.source_link_id,sectionId:row.section_id,
        unitIndex:row.unit_index,updatedAt:row.updated_at}):null;
    },
    clearReaderPosition({contentId}={}){
      id(contentId);
      return transact(db,()=>{
        assertContent(db,contentId);
        const result=db.prepare(
          "UPDATE reading_sessions SET session_state='abandoned',updated_at=? "+
          "WHERE content_id=? AND session_state='active'"
        ).run(clock(),contentId);
        return Object.freeze({status:result.changes?"abandoned":"no_active_session"});
      });
    }
  };
  return Object.freeze(api); // deliberately does not expose arbitrary SQL/db
}
export async function createTrustedInMemoryV2Runtime(){
  const db=new DatabaseSync(":memory:");
  try{
    initializeFreshV2Database(db,await loadReviewedFreshV2Sql());
    const runtime=bindTrustedFreshV2Sqlite(db);
    return Object.freeze({runtime,close:()=>db.close()});
  }catch(e){db.close();throw e;}
}
