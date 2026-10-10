// Pure host-side identity derivation for future canonical LegacyRecordMapping.
// NO persistent mapping, allocations, new Content IDs, or user-approval here.
import { createHash, randomUUID } from "node:crypto";

export class LegacyIdentityError extends Error {
  constructor(code) { super(code); this.name = "LegacyIdentityError"; this.code = code; }
}
const KINDS = Object.freeze({
  "local.db": new Set(["comics"]),
  "history.db": new Set(["history", "image_favorites"]),
  "local_favorite.db": new Set(["folder_item"]),
  "appdata.json": new Set(["settings"]),
  "implicitData.json": new Set(["implicit"]),
});
const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
function component(value, kind, allowEmpty=false) {
  if (typeof value !== "string" || (!allowEmpty && value.length===0) ||
      value.includes("\0") || Buffer.byteLength(value,"utf8") > 4096)
    throw new LegacyIdentityError("LEGACY_RECORD_KEY_INVALID_" + kind);
  return value;
}
export function newProvisionalDatasetId() {
  // Generate only following a trusted host action; persistence belongs to
  // LegacyImportDatasetRepository in the canonical v2 database, NOT here.
  return randomUUID();
}
export function legacyRecordIdentity({
  datasetId, fileRole, tableKind, scopeKey="", legacyTypeKey="", legacyId,
}) {
  if (typeof datasetId !== "string" || !UUID_V4.test(datasetId))
    throw new LegacyIdentityError("LEGACY_DATASET_ID_INVALID");
  if (!Object.hasOwn(KINDS,fileRole) || !KINDS[fileRole].has(tableKind))
    throw new LegacyIdentityError("LEGACY_RECORD_KIND_UNSUPPORTED");
  const tuple = [
    datasetId, fileRole, tableKind,
    component(scopeKey,"SCOPE",true),
    component(legacyTypeKey,"TYPE",true),
    component(legacyId,"ID"),
  ];
  if (fileRole==="local_favorite.db" && !tuple[3])
    throw new LegacyIdentityError("LEGACY_FAVORITE_FOLDER_REQUIRED");
  if (["local.db","history.db"].includes(fileRole) && !tuple[4])
    throw new LegacyIdentityError("LEGACY_RECORD_TYPE_REQUIRED");
  if (tableKind==="image_favorites" && !tuple[4])
    throw new LegacyIdentityError("LEGACY_RECORD_SOURCE_REQUIRED");
  // JSON array tuple is length-/boundary-unambiguous. Hash is only an opaque
  // local identity index, NOT a secret, capability, authorization or ContentId.
  const wire = JSON.stringify(["venera-legacy-record-v1", ...tuple]);
  return Object.freeze({
    keyDigest: createHash("sha256").update(wire).digest("hex"),
    // Caller may store normalized tuple in protected local canonical mapping DB.
    // Never export tuple or keyDigest in public CLI preview/logging.
    tuple: Object.freeze(tuple),
  });
}
