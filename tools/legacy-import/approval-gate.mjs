// Trusted host-only approval gate for L0/L1 one-time legacy import.
// Does not expose any plugin RPC, browser DOM, raw credentials or filesystem paths.
// The callbacks MUST be implemented by the trusted host UI and snapshot service.
// This is an integration contract; a host UI/immutable snapshot service is not yet wired.
import { createHash, randomUUID } from "node:crypto";

const ROLES = ["local.db","history.db","local_favorite.db","appdata.json","implicitData.json"];
const ROLE_SET = new Set(ROLES);
const SHA = /^[0-9a-f]{64}$/;
export class LegacyApprovalError extends Error {
  constructor(code) { super(code); this.name="LegacyApprovalError"; this.code=code; }
}
function fail(code) { throw new LegacyApprovalError(code); }
function textValue(value, max = 256) {
  if (typeof value !== "string" || !value || value.length > max || value.includes("\0"))
    fail("LEGACY_PLAN_INVALID");
  return value;
}
function normalizeManifest(manifest) {
  if (!Array.isArray(manifest) || manifest.length < 1 || manifest.length > ROLES.length)
    fail("LEGACY_PLAN_INVALID");
  const keys = new Set();
  const safe = manifest.map(entry => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry) ||
        Object.keys(entry).sort().join(",") !== "role,sha256" ||
        !ROLE_SET.has(entry.role) || !SHA.test(entry.sha256) || keys.has(entry.role))
      fail("LEGACY_PLAN_INVALID");
    keys.add(entry.role);
    return Object.freeze({role:entry.role,sha256:entry.sha256});
  }).sort((a,b)=>ROLES.indexOf(a.role)-ROLES.indexOf(b.role));
  return Object.freeze(safe);
}
export function makeTrustedPreviewPlan({ownerScopeId,datasetId,leaseRef,inputManifest,policyRevision,
  datasetIntent="existing",newDatasetLabel=null}) {
  textValue(ownerScopeId); textValue(datasetId); textValue(policyRevision,64);
  // Dataset ID is an immutable canonical UUID, not a filename, pluginKey or path.
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(datasetId) ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(leaseRef))
    fail("LEGACY_PLAN_INVALID");
  if (!["existing","new"].includes(datasetIntent)) fail("LEGACY_PLAN_INVALID");
  if (datasetIntent==="new") textValue(newDatasetLabel);
  else if (newDatasetLabel!==null) fail("LEGACY_PLAN_INVALID");
  const manifest=normalizeManifest(inputManifest);
  const body={ownerScopeId,datasetId,leaseRef,datasetIntent,newDatasetLabel,policyRevision,
    inputManifest:manifest.map(x=>({role:x.role,sha256:x.sha256}))};
  const planDigest=createHash("sha256").update(JSON.stringify(["legacy-import-plan-v1",body])).digest("hex");
  return Object.freeze({...body,inputManifest:manifest,planDigest});
}

export class TrustedLegacyApprovalService {
  #db; #verifyGesture; #leases;
  constructor({canonicalDb,verifyTrustedUserGesture,snapshotLeaseRegistry}) {
    if (!canonicalDb || typeof canonicalDb.prepare!=="function" ||
        typeof verifyTrustedUserGesture!=="function" ||
        !snapshotLeaseRegistry || typeof snapshotLeaseRegistry.verify!=="function" ||
        typeof snapshotLeaseRegistry.getManifest!=="function")
      fail("LEGACY_TRUSTED_HOST_REQUIRED");
    this.#db=canonicalDb;
    this.#verifyGesture=verifyTrustedUserGesture;
    this.#leases=snapshotLeaseRegistry;
  }
  // A plan is built from the private pinned snapshot manifest, never from
  // a renderer/plugin-supplied hash list or mutable original filesystem paths.
  createPlanForLease({ownerScopeId,datasetId,leaseRef,policyRevision,
    datasetIntent="existing",newDatasetLabel=null}) {
    const inputManifest=this.#leases.getManifest({leaseRef,ownerScopeId,datasetId});
    if (!inputManifest)fail("LEGACY_APPROVAL_STALE");
    return makeTrustedPreviewPlan({ownerScopeId,datasetId,leaseRef,policyRevision,
      datasetIntent,newDatasetLabel,inputManifest});
  }
  // The caller must be the trusted Venera user-gesture UI service.
  // No approval is possible from L0's stats-only CLI or a third-party plugin.
  async approve({plan,gesture,expectedPlanDigest}) {
    if (!plan || typeof plan!=="object" || typeof expectedPlanDigest!=="string")
      fail("LEGACY_APPROVAL_INVALID");
    // Recompute the complete reviewed plan; don't trust caller's hash.
    const validated=makeTrustedPreviewPlan(plan);
    if (plan.planDigest!==validated.planDigest || expectedPlanDigest!==validated.planDigest)
      fail("LEGACY_APPROVAL_PLAN_MISMATCH");
    let gestureOk=false,snapshotsOk=false;
    try {
      gestureOk=await this.#verifyGesture(gesture, {
        ownerScopeId:validated.ownerScopeId,datasetId:validated.datasetId,
        planDigest:validated.planDigest
      });
    } catch { fail("LEGACY_APPROVAL_GESTURE_REJECTED"); }
    if (gestureOk!==true)fail("LEGACY_APPROVAL_GESTURE_REJECTED");
    try {
      snapshotsOk=this.#leases.verify({
        leaseRef:validated.leaseRef,ownerScopeId:validated.ownerScopeId,
        datasetId:validated.datasetId,inputManifest:validated.inputManifest
      });
    } catch { fail("LEGACY_APPROVAL_STALE"); }
    if (snapshotsOk!==true)fail("LEGACY_APPROVAL_STALE");
    // No await after lease verification. SQLite transaction starts before lookup/write.
    // The validated *memory copy* is independent of changes to the user's old files.
    const db=this.#db,id=randomUUID(),stamp=new Date().toISOString();
    db.exec("BEGIN IMMEDIATE");
    try {
      if (validated.datasetIntent==="new") {
        const exists=db.prepare("SELECT id FROM legacy_import_datasets WHERE id=?")
          .get(validated.datasetId);
        if (exists)fail("LEGACY_APPROVAL_DATASET_CONFLICT");
        db.prepare(
          "INSERT INTO legacy_import_datasets "+
          "(id,owner_scope_id,display_label,state,created_at,updated_at) "+
          "VALUES (?,?,?,'active',?,?)"
        ).run(validated.datasetId,validated.ownerScopeId,validated.newDatasetLabel,stamp,stamp);
      } else {
        const owner=db.prepare(
          "SELECT id FROM legacy_import_datasets WHERE id=? AND owner_scope_id=? AND state='active'"
        ).get(validated.datasetId,validated.ownerScopeId);
        if (!owner)fail("LEGACY_APPROVAL_DATASET_DENIED");
      }
      db.prepare(
        "INSERT INTO legacy_import_batches "+
        "(id,dataset_id,input_manifest_json,policy_revision,plan_digest,snapshot_lease_ref,state,created_at,approved_at,updated_at) "+
        "VALUES (?,?,?,?,?,?,'approved',?,?,?)"
      ).run(id,validated.datasetId,JSON.stringify(validated.inputManifest),
        validated.policyRevision,validated.planDigest,validated.leaseRef,stamp,stamp,stamp);
      db.exec("COMMIT");
    } catch(e) {
      db.exec("ROLLBACK");
      throw e;
    }
    // Output is a host-private batch ID. Never return to untrusted plugin JS.
    return Object.freeze({batchId:id,planDigest:validated.planDigest});
  }
}
