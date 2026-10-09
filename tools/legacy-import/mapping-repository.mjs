// Trusted-host canonical v2 LegacyImportDataset + LegacyRecordMapping adapter.
// No schema creation, no source parser, no plugin RPC, no separate sidecar DB.
// Tables come ONLY from docs/design/v2/02_DATABASE_SCHEMA.md.
import { randomUUID } from "node:crypto";
import { legacyRecordIdentity } from "./record-identity.mjs";

export class MappingStoreError extends Error {
  constructor(code) { super(code); this.name="MappingStoreError"; this.code=code; }
}
const now = () => new Date().toISOString();
function requireText(s) {
  if(typeof s!=="string" || !s || s.length>256 || s.includes("\0"))
    throw new MappingStoreError("LEGACY_MAPPING_INVALID_INPUT");
  return s;
}
function tx(db, action) {
  db.exec("BEGIN IMMEDIATE");
  try {
    const out=action();
    db.exec("COMMIT");
    return out;
  } catch (err) {
    db.exec("ROLLBACK");
    throw err;
  }
}
export class LegacyMappingRepository {
  constructor(trustedCanonicalDb) {
    // Not a security check: caller must be the host-only approved UC-LGI service.
    // No arbitrary SQL, path, filename, cookie or plugin value is accepted here.
    this.db=trustedCanonicalDb;
  }
  createDatasetForApprovedImport({ownerScopeId,displayLabel}) {
    requireText(ownerScopeId);
    requireText(displayLabel);
    const id=randomUUID(), time=now();
    this.db.prepare(
      "INSERT INTO legacy_import_datasets(id,owner_scope_id,display_label,state,created_at,updated_at) VALUES (?,?,?,?,?,?)"
    ).run(id,ownerScopeId,displayLabel,"active",time,time);
    return id;
  }
  findDataset({ownerScopeId,datasetId}) {
    requireText(ownerScopeId); requireText(datasetId);
    return this.db.prepare(
      "SELECT id,state FROM legacy_import_datasets WHERE id=? AND owner_scope_id=?"
    ).get(datasetId,ownerScopeId)??null;
  }
  lookupMapping({ownerScopeId,key}) {
    requireText(ownerScopeId);
    const {tuple}=legacyRecordIdentity(key);
    const [datasetId,fileRole,tableKind,scopeKey,legacyTypeKey,legacyId]=tuple;
    const row=this.db.prepare(
      "SELECT m.id,m.mapping_state,m.source_record_digest,m.target_content_id FROM legacy_record_mappings m "+
      "JOIN legacy_import_datasets d ON d.id=m.dataset_id WHERE d.owner_scope_id=? AND "+
      "m.dataset_id=? AND m.file_role=? AND m.table_kind=? AND m.scope_key=? AND "+
      "m.legacy_type_key=? AND m.legacy_id=?"
    ).get(ownerScopeId,datasetId,fileRole,tableKind,scopeKey,legacyTypeKey,legacyId);
    return row??null;
  }
  reserveAfterApprovedPlan({ownerScopeId,key,recordDigest}) {
    requireText(ownerScopeId);
    if(typeof recordDigest!=="string" || !/^[a-f0-9]{64}$/.test(recordDigest))
      throw new MappingStoreError("LEGACY_MAPPING_DIGEST_INVALID");
    const {tuple}=legacyRecordIdentity(key);
    const [datasetId,fileRole,tableKind,scopeKey,legacyTypeKey,legacyId]=tuple;
    return tx(this.db,()=>{
      const owner=this.db.prepare(
        "SELECT state FROM legacy_import_datasets WHERE id=? AND owner_scope_id=?"
      ).get(datasetId,ownerScopeId);
      if(!owner || owner.state!=="active")
        throw new MappingStoreError("LEGACY_MAPPING_SCOPE_DENIED");
      const before=this.lookupMapping({ownerScopeId,key});
      if(before) {
        if(before.mapping_state==="tombstoned")return {state:"tombstoned",mappingId:before.id};
        if(before.source_record_digest===recordDigest)
          return {state:"existing",mappingId:before.id,mappingState:before.mapping_state};
        this.db.prepare(
          "UPDATE legacy_record_mappings SET mapping_state='changed_pending',updated_at=? WHERE id=?"
        ).run(now(),before.id);
        return {state:"changed_pending",mappingId:before.id};
      }
      const id=randomUUID(),time=now();
      this.db.prepare(
        "INSERT INTO legacy_record_mappings"+
        "(id,dataset_id,file_role,table_kind,scope_key,legacy_type_key,legacy_id,"+
        "source_record_digest,mapping_state,evidence_revision,created_at,updated_at) "+
        "VALUES (?,?,?,?,?,?,?,?,'unresolved',1,?,?)"
      ).run(id,datasetId,fileRole,tableKind,scopeKey,legacyTypeKey,legacyId,recordDigest,time,time);
      return {state:"reserved_unresolved",mappingId:id};
    });
  }
}
