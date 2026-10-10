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
  #leases;
  constructor(trustedCanonicalDb,{snapshotLeaseRegistry}={}) {
    // Trusted host wiring only. No untrusted plugin RPC can hold this registry.
    // Without the pinned snapshot lease, every mutation MUST fail closed.
    this.db=trustedCanonicalDb;
    this.#leases=snapshotLeaseRegistry;
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
  reserveAfterApprovedPlan({ownerScopeId,batchId,expectedPlanDigest,key,recordDigest}) {
    requireText(ownerScopeId);
    if (typeof batchId!=="string" || !batchId ||
        batchId.length>256 || batchId.includes("\0"))
      throw new MappingStoreError("LEGACY_APPROVAL_REQUIRED");
    if(typeof expectedPlanDigest!=="string" || !/^[0-9a-f]{64}$/.test(expectedPlanDigest))
      throw new MappingStoreError("LEGACY_APPROVAL_REQUIRED");
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
      const batch=this.db.prepare(
        "SELECT b.id,b.state,b.plan_digest,b.approval_scope,b.input_manifest_json,b.snapshot_lease_ref FROM legacy_import_batches b "+
        "JOIN legacy_import_datasets d ON d.id=b.dataset_id "+
        "WHERE b.id=? AND b.dataset_id=? AND d.owner_scope_id=?"
      ).get(batchId,datasetId,ownerScopeId);
      if(!batch || !["approved","applying"].includes(batch.state) ||
          batch.approval_scope!=="evidence_only" ||
          batch.plan_digest!==expectedPlanDigest)
        throw new MappingStoreError("LEGACY_APPROVAL_REQUIRED");
      let manifest;
      try { manifest=JSON.parse(batch.input_manifest_json); }
      catch { throw new MappingStoreError("LEGACY_APPROVAL_REQUIRED"); }
      if(!Array.isArray(manifest) ||
          !manifest.some(e=>e && e.role===fileRole && /^[a-f0-9]{64}$/.test(e.sha256)))
        throw new MappingStoreError("LEGACY_APPROVAL_ROLE_DENIED");
      // The approval is NOT a permanent grant. It is bound to the still-live,
      // immutable, owner-scoped snapshot lease. App restart/expiration fails closed.
      if(!this.#leases || typeof this.#leases.verify!=="function" ||
          !this.#leases.verify({
            leaseRef:batch.snapshot_lease_ref,ownerScopeId,datasetId,inputManifest:manifest
          }))
        throw new MappingStoreError("LEGACY_SNAPSHOT_STALE");
      // A valid file role is NOT enough. The record key and exact digest must
      // be attested inside the approved immutable snapshot.
      // Only local.db/comics evidence is implemented; all other kinds deny.
      if(typeof this.#leases.verifyRecord!=="function" ||
          !this.#leases.verifyRecord({
            leaseRef:batch.snapshot_lease_ref,ownerScopeId,datasetId,
            inputManifest:manifest,key,recordDigest
          }))
        throw new MappingStoreError("LEGACY_RECORD_UNATTESTED");
      // This only reserves identity evidence; no Content/Unit storage commit. The future
      // importer MUST independently prove that each record came from the
      // still-pinned approved snapshot before any canonical content write.
      const before=this.lookupMapping({ownerScopeId,key});
      if(before) {
        if(before.mapping_state==="tombstoned")return {state:"tombstoned",mappingId:before.id};
        if(before.source_record_digest===recordDigest)
          return {state:"existing",mappingId:before.id,mappingState:before.mapping_state};
        this.db.prepare(
          "UPDATE legacy_record_mappings SET mapping_state='changed_pending',last_batch_id=?,updated_at=? WHERE id=?"
        ).run(batchId,now(),before.id);
        return {state:"changed_pending",mappingId:before.id};
      }
      const id=randomUUID(),time=now();
      this.db.prepare(
        "INSERT INTO legacy_record_mappings"+
        "(id,dataset_id,file_role,table_kind,scope_key,legacy_type_key,legacy_id,"+
        "source_record_digest,mapping_state,last_batch_id,evidence_revision,created_at,updated_at) "+
        "VALUES (?,?,?,?,?,?,?,?,'unresolved',?,1,?,?)"
      ).run(id,datasetId,fileRole,tableKind,scopeKey,legacyTypeKey,legacyId,recordDigest,batchId,time,time);
      return {state:"reserved_unresolved",mappingId:id};
    });
  }
}
