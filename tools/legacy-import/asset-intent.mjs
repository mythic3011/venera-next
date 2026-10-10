// Trusted host-only L1 contract slice: separate consent to prepare ONE local
// asset intent. NO file copying, canonical Content, StorageObject or session write.
// Do not expose the service / asset bytes / gesture authority through web/JS RPC.
import { createHash, randomUUID } from "node:crypto";
import { legacyRecordIdentity } from "./record-identity.mjs";

export class AssetPreparationError extends Error {
  constructor(code) { super(code); this.name="AssetPreparationError"; this.code=code; }
}
function deny(code) { throw new AssetPreparationError(code); }
const SHA=/^[a-f0-9]{64}$/;
const MAX_ASSET=64*1024*1024;
const HASH=(v)=>createHash("sha256").update(v).digest("hex");
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;

export class TrustedLegacyAssetIntentService {
  #db; #leases; #gestures; #plans=new WeakMap();
  constructor({canonicalDb,snapshotLeaseRegistry,gestureAuthority}) {
    if(!canonicalDb || typeof canonicalDb.prepare!=="function" ||
       !snapshotLeaseRegistry || typeof snapshotLeaseRegistry.verifyRecord!=="function" ||
       !gestureAuthority || typeof gestureAuthority.confirm!=="function" ||
       typeof gestureAuthority.verifyTrustedUserGesture!=="function")
      deny("ASSET_HOST_REQUIRED");
    this.#db=canonicalDb; this.#leases=snapshotLeaseRegistry;
    this.#gestures=gestureAuthority;
  }
  #batch({ownerScopeId,batchId,key,recordDigest}) {
    if(typeof ownerScopeId!=="string" || !ownerScopeId || !UUID.test(batchId) ||
       !SHA.test(recordDigest) || key?.fileRole!=="local.db" ||
       key?.tableKind!=="comics")deny("ASSET_SCOPE_DENIED");
    const datasetId=key.datasetId;
    if(!UUID.test(datasetId))deny("ASSET_SCOPE_DENIED");
    const b=this.#db.prepare(
      "SELECT b.id,b.plan_digest,b.input_manifest_json,b.snapshot_lease_ref, "+
      "b.approval_scope,b.state FROM legacy_import_batches b "+
      "JOIN legacy_import_datasets d ON d.id=b.dataset_id "+
      "WHERE b.id=? AND b.dataset_id=? AND d.owner_scope_id=? AND d.state='active'"
    ).get(batchId,datasetId,ownerScopeId);
    if(!b || b.approval_scope!=="evidence_only" ||
       !["approved","applying"].includes(b.state))
      deny("ASSET_EVIDENCE_APPROVAL_REQUIRED");
    let manifest;
    try {manifest=JSON.parse(b.input_manifest_json);}
    catch{deny("ASSET_EVIDENCE_APPROVAL_REQUIRED");}
    if(!Array.isArray(manifest) || !manifest.some(x=>x.role==="local.db"&&SHA.test(x.sha256)))
      deny("ASSET_ROLE_UNAVAILABLE");
    if(!this.#leases.verifyRecord({
      leaseRef:b.snapshot_lease_ref,ownerScopeId,datasetId,
      inputManifest:manifest,key,recordDigest
    }))deny("ASSET_RECORD_UNATTESTED");
    return {datasetId,planDigest:b.plan_digest,leaseRef:b.snapshot_lease_ref};
  }
  // assetBytes MUST come from a separately approved local media-root resolver,
  // not the old DB's directory string, an HTTP URL, plugin JS or a caller path.
  // The resolver is NOT implemented in the current greenfield slice.
  inspect({ownerScopeId,batchId,mappingId,key,recordDigest,assetBytes}) {
    if(!(Buffer.isBuffer(assetBytes) || assetBytes instanceof Uint8Array) ||
       assetBytes.byteLength<1 || assetBytes.byteLength>MAX_ASSET)
      deny("ASSET_BYTES_INVALID");
    const batch=this.#batch({ownerScopeId,batchId,key,recordDigest});
    if(!UUID.test(mappingId))deny("ASSET_MAPPING_REQUIRED");
    const mapping=this.#db.prepare(
      "SELECT m.id FROM legacy_record_mappings m "+
      "JOIN legacy_import_datasets d ON d.id=m.dataset_id "+
      "WHERE m.id=? AND d.owner_scope_id=? AND m.dataset_id=? "+
      "AND m.file_role='local.db' AND m.table_kind='comics' "+
      "AND m.scope_key=? AND m.legacy_type_key=? AND m.legacy_id=? "+
      "AND m.source_record_digest=? AND m.mapping_state IN ('unresolved','unchanged')"
    ).get(mappingId,ownerScopeId,key.datasetId,
      key.scopeKey??"",key.legacyTypeKey,key.legacyId,recordDigest);
    if(!mapping)deny("ASSET_MAPPING_REQUIRED");
    const identity=legacyRecordIdentity(key);
    const expectedSha256=HASH(assetBytes);
    const expectedBytes=assetBytes.byteLength;
    const body=["legacy-asset-intent-v1","plan_only",ownerScopeId,batchId,
      batch.datasetId,batch.planDigest,mappingId,identity.keyDigest,recordDigest,
      expectedSha256,expectedBytes];
    const assetPlanDigest=HASH(Buffer.from(JSON.stringify(body)));
    // No user path, original title, secret or source DB content in UI preview.
    const view=Object.freeze({category:"local_comic_asset",
      actionScope:"plan_only",byteCount:expectedBytes,
      sha256Prefix:expectedSha256.slice(0,12),canCopy:false,canCommit:false});
    const plan=Object.freeze(Object.create(null));
    this.#plans.set(plan,{ownerScopeId,batchId,mappingId,key:Object.freeze({...key}),
      recordDigest,identityDigest:identity.keyDigest,
      assetPlanDigest,expectedSha256,expectedBytes,leaseRef:batch.leaseRef,
      batchPlanDigest:batch.planDigest,used:false});
    return Object.freeze({plan,preview:view});
  }
  async authorizeAndRecordIntent({plan,preview}) {
    const state=this.#plans.get(plan);
    if(!state || state.used)deny("ASSET_PLAN_INVALID");
    state.used=true; // consume even if user cancels
    const {ownerScopeId,batchId,mappingId,key,recordDigest}=state;
    const context={ownerScopeId,datasetId:key.datasetId,
      planDigest:state.assetPlanDigest};
    // Gesture authority is a DIFFERENT challenge from L0 evidence approval.
    // Future native UI must explicitly display the scope and source asset grant.
    const gesture=await this.#gestures.confirm(context,preview);
    if(await this.#gestures.verifyTrustedUserGesture(gesture,context)!==true)
      deny("ASSET_GESTURE_REJECTED");
    // Revalidate after human delay; no await between revalidation and DB txn.
    const b=this.#batch({ownerScopeId,batchId,key,recordDigest});
    if(b.planDigest!==state.batchPlanDigest || b.leaseRef!==state.leaseRef)
      deny("ASSET_APPROVAL_CHANGED");
    const db=this.#db;
    const id=randomUUID(),storageId=randomUUID(),stamp=new Date().toISOString();
    db.exec("BEGIN IMMEDIATE");
    try {
      // Repeat owner/batch status and lease validation under SQLite write lock.
      const locked=this.#batch({ownerScopeId,batchId,key,recordDigest});
      if(locked.planDigest!==state.batchPlanDigest ||
         locked.leaseRef!==state.leaseRef)deny("ASSET_APPROVAL_CHANGED");
      const mapped=db.prepare(
        "SELECT m.id FROM legacy_record_mappings m "+
        "WHERE m.id=? AND m.dataset_id=? AND m.file_role='local.db' "+
        "AND m.table_kind='comics' AND m.scope_key=? AND m.legacy_type_key=? "+
        "AND m.legacy_id=? AND m.source_record_digest=? "+
        "AND m.mapping_state IN ('unresolved','unchanged')"
      ).get(mappingId,key.datasetId,key.scopeKey??"",key.legacyTypeKey,
        key.legacyId,recordDigest);
      if(!mapped)deny("ASSET_MAPPING_REQUIRED");
      db.prepare(
        "INSERT INTO legacy_asset_journal "+
        "(id,batch_id,mapping_id,planned_storage_id,staging_ref,expected_sha256,"+
        "expected_bytes,state,authorization_scope,authorization_digest,created_at,updated_at) "+
        "VALUES (?,?,?,?,?,?,?,'planned','plan_only',?,?,?)"
      ).run(id,batchId,mappingId,storageId,"intent:"+id,state.expectedSha256,
        state.expectedBytes,state.assetPlanDigest,stamp,stamp);
      db.exec("COMMIT");
    }catch(err){db.exec("ROLLBACK");throw err;}
    return Object.freeze({status:"asset_intent_planned",canCopy:false,
      canCommit:false,journalId:id});
  }
}
