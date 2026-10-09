// Host-side interaction coordinator. It MUST run in a trusted main process /
// local console, never be exposed as a renderer, website, HTTP or plugin RPC.
// L0 scope ONLY: preview and approve an EVIDENCE batch; NO content import.
import { newProvisionalDatasetId } from "./record-identity.mjs";
import { TrustedLegacyApprovalService } from "./approval-gate.mjs";
import { previewAndIssueSnapshotLease } from "./docker-sandbox.mjs";

export class LegacyWizardError extends Error {
  constructor(code) { super(code); this.name="LegacyWizardError"; this.code=code; }
}
function fail(code) { throw new LegacyWizardError(code); }

export async function runTrustedEvidenceWizard({
  selectedDirectory, ownerScopeId, canonicalDb,
  datasetIntent="new", datasetId=null, newDatasetLabel=null,
  snapshotLeaseRegistry, gestureAuthority,
  // Test seam only; production MUST use previewAndIssueSnapshotLease.
  snapshotter=previewAndIssueSnapshotLease
}) {
  if(typeof ownerScopeId!=="string" || !ownerScopeId ||
     !canonicalDb || typeof canonicalDb.prepare!=="function" ||
     !snapshotLeaseRegistry || typeof snapshotLeaseRegistry.revoke!=="function" ||
     !gestureAuthority || typeof gestureAuthority.confirm!=="function" ||
     typeof gestureAuthority.verifyTrustedUserGesture!=="function" ||
     typeof snapshotter!=="function" ||
     !["new","existing"].includes(datasetIntent))
    fail("WIZARD_HOST_INTEGRATION_INVALID");
  if(datasetIntent==="new") {
    if(datasetId!==null || typeof newDatasetLabel!=="string" ||
       !newDatasetLabel.trim() || newDatasetLabel.length>256)
      fail("WIZARD_DATASET_SELECTION_INVALID");
    datasetId=newProvisionalDatasetId();
  } else {
    if(typeof datasetId!=="string" || newDatasetLabel!==null)
      fail("WIZARD_DATASET_SELECTION_INVALID");
    const existing=canonicalDb.prepare(
      "SELECT id FROM legacy_import_datasets "+
      "WHERE id=? AND owner_scope_id=? AND state='active'"
    ).get(datasetId,ownerScopeId);
    if(!existing)fail("WIZARD_DATASET_NOT_FOUND");
  }
  let leaseRef=null;
  let approved=false;
  try {
    const {preview,leaseRef:ref}=await snapshotter({
      selectedDirectory,ownerScopeId,datasetId,snapshotLeaseRegistry
    });
    leaseRef=ref;
    // Result is the trusted host's bounded/public preview; do not use a
    // renderer-supplied counts object to justify approval.
    if(preview?.status!=="preview_only" || preview?.canCommit!==false ||
       !Array.isArray(preview.files) || preview.files.length!==5)
      fail("WIZARD_PREVIEW_UNAVAILABLE");
    const gate=new TrustedLegacyApprovalService({
      canonicalDb,snapshotLeaseRegistry,
      verifyTrustedUserGesture:gestureAuthority.verifyTrustedUserGesture
    });
    const plan=gate.createPlanForLease({
      ownerScopeId,datasetId,leaseRef,policyRevision:"l0-evidence-only-v1",
      datasetIntent,newDatasetLabel
    });
    const context={ownerScopeId,datasetId,planDigest:plan.planDigest};
    const gesture=await gestureAuthority.confirm(context,preview);
    const batch=await gate.approve({
      plan,gesture,expectedPlanDigest:plan.planDigest
    });
    approved=true;
    // Deliberately do not return or log the lease, plan, input hashes or
    // raw old source data. Batch ID remains a trusted host-internal handle.
    return Object.freeze({
      status:"evidence_approved",
      scope:"evidence_only",
      importedContents:0,
      importedSettings:0,
      importedReaderPositions:0,
      batchId:batch.batchId
    });
  }finally{
    // Denied/cancelled/broken approval cannot leave an actionable lease.
    if(!approved && leaseRef) {
      snapshotLeaseRegistry.revoke({leaseRef,ownerScopeId,datasetId});
    }
  }
}
