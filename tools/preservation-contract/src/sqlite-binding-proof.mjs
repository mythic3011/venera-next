// Test-only SQLite transactional reference. Not PR #6 runtime or production authority.
// Requires a trusted host DB handle + an explicit TEST-ONLY owner registry.
import { fingerprintCanonicalOrder } from './canonical-publish-gate.mjs';

const ID=/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const SHA=/^[0-9a-f]{64}$/;
function deny(code){const e=new Error(code);e.code=code;throw e;}
const valid=v=>typeof v==='string'&&ID.test(v);

function trustedSchema(db) {
  if (!db || typeof db.prepare!=='function' || typeof db.exec!=='function')
    deny('DB_REQUIRED');
  if (db.prepare('PRAGMA foreign_keys').get().foreign_keys!==1)
    deny('FOREIGN_KEYS_REQUIRED');
  const expected=[
    'contents','content_sections','content_units','content_unit_orders',
    'content_unit_order_items','storage_objects','storage_placements',
    'v2_storage_write_journal','proof_content_owners',
    'proof_preservation_snapshots','proof_preservation_pages',
  ];
  const found=new Set(db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map(r=>r.name));
  if (expected.some(name=>!found.has(name))) deny('PROOF_SCHEMA_REQUIRED');
}
function readOrder(db, {ownerScopeId,contentId,sectionId}) {
  if (![ownerScopeId,contentId,sectionId].every(valid)) deny('INVALID_SCOPE');
  const authorized=db.prepare(
    "SELECT 1 FROM proof_content_owners WHERE owner_scope_id=? AND content_id=?"
  ).get(ownerScopeId,contentId);
  if (!authorized) deny('OWNER_SCOPE_DENIED');
  const section=db.prepare(
    "SELECT s.id FROM content_sections s JOIN contents c ON c.id=s.content_id "+
    "WHERE s.id=? AND s.content_id=? AND c.library_status='active'"
  ).get(sectionId,contentId);
  if(!section)deny('SECTION_UNAVAILABLE');
  const source=db.prepare(
    "SELECT id,unit_index FROM content_units WHERE section_id=? ORDER BY unit_index,id"
  ).all(sectionId);
  if(source.length===0||source.length>128)deny('CANONICAL_ORDER_INVALID');
  const order=db.prepare(
    "SELECT id FROM content_unit_orders WHERE section_id=? AND status='active'"
  ).get(sectionId);
  if(!order)return {units:source};
  const items=db.prepare(
    "SELECT i.unit_id AS id,u.unit_index,u.section_id FROM content_unit_order_items i "+
    "LEFT JOIN content_units u ON u.id=i.unit_id "+
    "WHERE i.order_id=? ORDER BY i.sort_index"
  ).all(order.id);
  const ids=new Set(source.map(x=>x.id));
  if(items.length!==source.length||new Set(items.map(x=>x.id)).size!==source.length||
    items.some(x=>x.section_id!==sectionId||!ids.has(x.id)))deny('ACTIVE_ORDER_INVALID');
  return {units:items.map(({id,unit_index})=>({id,unit_index}))};
}
/**
 * Bridge shape matches publishPreservedSnapshot's canonical port.
 * Pass a trusted native-host lease verifier. The fixture's callback is NOT
 * a real OS user gesture, capability token, or filesystem pin.
 */
export function createSqliteBindingProof({db,assertActiveLease,checkpoint=()=>{}}) {
  trustedSchema(db);
  if(typeof assertActiveLease!=='function'||typeof checkpoint!=='function')
    deny('TRUSTED_LEASE_REQUIRED');
  const readSectionOrder=scope=>{
    const {units}=readOrder(db,scope);
    return {units:units.map(u=>({id:u.id,unitIndex:u.unit_index}))};
  };
  function commitPreservationBinding(input) {
    if (!input || typeof input!=='object' || !Array.isArray(input.links) ||
      ![input.ownerScopeId,input.snapshotId,input.contentId,input.sectionId].every(valid) ||
      !SHA.test(input.manifestSha256)||!SHA.test(input.expectedOrderDigest)||
      input.links.length<1||input.links.length>128)deny('INVALID_BINDING');
    let began=false;
    try{
      db.exec('BEGIN IMMEDIATE');
      began=true;
      const current=readSectionOrder({
        ownerScopeId:input.ownerScopeId,contentId:input.contentId,sectionId:input.sectionId
      });
      const currentDigest=fingerprintCanonicalOrder({
        contentId:input.contentId,sectionId:input.sectionId,units:current.units
      });
      if(currentDigest!==input.expectedOrderDigest)deny('ORDER_CHANGED_AT_COMMIT');
      if(input.links.length!==current.units.length)deny('INCOMPLETE_BINDING');
      const seen=new Set();
      for(let i=0;i<input.links.length;i++){
        const link=input.links[i],unit=current.units[i];
        if(!link || link.unitId!==unit.id || link.ordinal!==i ||
          !valid(link.storageObjectId)||!valid(link.placementId)||
          !SHA.test(link.sha256)||!Number.isSafeInteger(link.byteLength)||
          link.byteLength<1 || link.byteLength>32*1024*1024 ||
          seen.has(link.unitId))deny('PAGE_BINDING_INVALID');
        seen.add(link.unitId);
        const place=db.prepare(
          "SELECT p.id,p.storage_object_id,p.role,p.sync_status,"+
          "o.object_kind,o.content_hash,o.size_bytes FROM storage_placements p "+
          "JOIN storage_objects o ON o.id=p.storage_object_id WHERE p.id=?"
        ).get(link.placementId);
        if(!place||place.storage_object_id!==link.storageObjectId||
          !['authority','mirror'].includes(place.role)||place.sync_status!=='synced'||
          place.object_kind!=='unit_image'||place.content_hash!==link.sha256||
          place.size_bytes!==link.byteLength)deny('PLACEMENT_CHANGED_AT_COMMIT');
        const authorized=db.prepare(
          "SELECT 1 FROM v2_storage_write_journal WHERE planned_storage_id=? "+
          "AND planned_placement_id=? AND owner_scope_id=? AND state='committed' "+
          "AND authorization_scope='storage_object_only' AND expected_sha256=? AND expected_bytes=?"
        ).get(link.storageObjectId,link.placementId,input.ownerScopeId,link.sha256,link.byteLength);
        if(!authorized)deny('STORAGE_OWNER_OR_JOURNAL_INVALID');
      }
      // Trusted host must lock/pin verified physical bytes until commit.
      // Caller-supplied boolean from a plugin must NEVER satisfy this.
      if(assertActiveLease(input)!==true)deny('PRESERVATION_LEASE_REVOKED');
      const existing=db.prepare(
        'SELECT owner_scope_id,content_id,section_id,manifest_sha256,order_digest '+
        'FROM proof_preservation_snapshots WHERE id=?'
      ).get(input.snapshotId);
      if(existing){
        if(existing.owner_scope_id!==input.ownerScopeId||
          existing.content_id!==input.contentId||existing.section_id!==input.sectionId||
          existing.manifest_sha256!==input.manifestSha256||
          existing.order_digest!==input.expectedOrderDigest)deny('SNAPSHOT_ID_CONFLICT');
        const saved=db.prepare(
          "SELECT ordinal,unit_id,storage_object_id,placement_id,sha256,byte_length "+
          "FROM proof_preservation_pages WHERE snapshot_id=? ORDER BY ordinal"
        ).all(input.snapshotId);
        if(saved.length!==input.links.length||saved.some((p,i)=>p.ordinal!==i||
          p.unit_id!==input.links[i].unitId||
          p.storage_object_id!==input.links[i].storageObjectId||
          p.placement_id!==input.links[i].placementId||
          p.sha256!==input.links[i].sha256||
          p.byte_length!==input.links[i].byteLength))deny('SNAPSHOT_ID_CONFLICT');
        db.exec('COMMIT');began=false;
        return {state:'replayed',snapshotId:input.snapshotId,manifestSha256:input.manifestSha256};
      }
      const at=new Date().toISOString();
      db.prepare(
        "INSERT INTO proof_preservation_snapshots "+
        "(id,owner_scope_id,content_id,section_id,manifest_sha256,order_digest,"+
        "state,pinned,created_at) VALUES(?,?,?,?,?,?,'committed',1,?)"
      ).run(input.snapshotId,input.ownerScopeId,input.contentId,input.sectionId,
        input.manifestSha256,input.expectedOrderDigest,at);
      const insert=db.prepare(
        "INSERT INTO proof_preservation_pages "+
        "(snapshot_id,ordinal,unit_id,storage_object_id,placement_id,sha256,byte_length) "+
        "VALUES(?,?,?,?,?,?,?)"
      );
      for(let i=0;i<input.links.length;i++){
        const p=input.links[i];
        insert.run(input.snapshotId,p.ordinal,p.unitId,p.storageObjectId,
          p.placementId,p.sha256,p.byteLength);
        checkpoint({phase:'after_page_insert',ordinal:i});
      }
      db.exec('COMMIT');began=false;
      return {state:'committed',snapshotId:input.snapshotId,manifestSha256:input.manifestSha256};
    }catch(err){
      if(began)db.exec('ROLLBACK');
      throw err;
    }
  }
  return Object.freeze({readSectionOrder,commitPreservationBinding});
}
