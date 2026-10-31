/**
 * Pure backup media-closure planning only. No bytes are uploaded or copied.
 * Caller must be a trusted coordinator supplying verified, readable placement
 * evidence; do not pass raw provider/plugin claims as verifiedObjectIds.
 */
function reject(code, message) {
  const err = new Error(message);
  err.code = code;
  throw err;
}
const ID = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
function validateId(id, label) {
  if (typeof id !== 'string' || !ID.test(id)) reject('INVALID_INPUT', `${label} is not a valid identifier`);
}
function unique(values, label) {
  if (new Set(values).size !== values.length) reject('DUPLICATE_ID', `${label} contains duplicates`);
}
function exactKeys(value, keys, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) reject('INVALID_INPUT', `${label} must be an object`);
  if (Object.keys(value).some(key => !keys.includes(key))) reject('INVALID_INPUT', `${label} has unexpected fields`);
}

export function planBackupMediaInventory(input) {
  exactKeys(input, ['mode', 'snapshots', 'selectedSnapshotIds', 'verifiedObjectIds'], 'input');
  if (input.mode !== 'standard' && input.mode !== 'full') reject('INVALID_INPUT', 'unsupported backup mode');
  if (!Array.isArray(input.snapshots) || !Array.isArray(input.selectedSnapshotIds) || !Array.isArray(input.verifiedObjectIds)) {
    reject('INVALID_INPUT', 'backup inputs must be arrays');
  }
  for (const id of input.selectedSnapshotIds) validateId(id, 'selectedSnapshotId');
  for (const id of input.verifiedObjectIds) validateId(id, 'verifiedObjectId');
  unique(input.selectedSnapshotIds, 'selectedSnapshotIds');
  unique(input.verifiedObjectIds, 'verifiedObjectIds');
  const snapshots = new Map();
  for (const snapshot of input.snapshots) {
    exactKeys(snapshot, ['id', 'state', 'objectIds'], 'snapshot');
    validateId(snapshot.id, 'snapshot.id');
    if (snapshots.has(snapshot.id)) reject('DUPLICATE_ID', 'snapshot ID repeated');
    if (!['committed', 'partial', 'staging'].includes(snapshot.state) || !Array.isArray(snapshot.objectIds)) {
      reject('INVALID_INPUT', 'invalid snapshot state/objectIds');
    }
    snapshot.objectIds.forEach(v => validateId(v, 'snapshot.objectId'));
    unique(snapshot.objectIds, 'snapshot.objectIds');
    snapshots.set(snapshot.id, snapshot);
  }
  const requiredObjects = new Set();
  for (const id of input.selectedSnapshotIds) {
    const snapshot = snapshots.get(id);
    if (!snapshot) reject('UNKNOWN_SNAPSHOT', `selected snapshot ${id} does not exist`);
    if (snapshot.state !== 'committed') reject('NOT_COMMITTED', `snapshot ${id} is not committed`);
    for (const objectId of snapshot.objectIds) requiredObjects.add(objectId);
  }
  const requiredIds = [...requiredObjects].sort();
  const verified = new Set(input.verifiedObjectIds);
  const missing = requiredIds.filter(id => !verified.has(id));
  if (input.mode === 'full' && missing.length > 0) {
    reject('MEDIA_UNAVAILABLE', `full backup cannot include ${missing.length} unavailable objects`);
  }
  const omittedSnapshotIds = [...snapshots.keys()].filter(id => !input.selectedSnapshotIds.includes(id)).sort();
  return Object.freeze({
    mode: input.mode,
    selectedSnapshotIds: Object.freeze([...input.selectedSnapshotIds].sort()),
    omittedSnapshotIds: Object.freeze(omittedSnapshotIds),
    requiredMediaObjectIds: Object.freeze(requiredIds),
    mediaObjectIdsToTransfer: Object.freeze(input.mode === 'full' ? requiredIds : []),
    mediaObjectIdsNotIncluded: Object.freeze(input.mode === 'standard' ? requiredIds : []),
    // Only an eligibility hint: transport, ciphertext integrity, and restore not proven.
    completeMediaCandidate: input.mode === 'full' && requiredIds.length > 0,
  });
}
