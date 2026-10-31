import { createHash } from 'node:crypto';

const MAX_IMAGE_BYTES = 32 * 1024 * 1024;
const ID = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);

function fail(code, message) {
  const error = new Error(message);
  error.code = code;
  throw error;
}

function requireId(value, field) {
  if (typeof value !== 'string' || !ID.test(value)) {
    fail('INVALID_INPUT', `${field} must be a bounded nonempty identifier`);
  }
  return value;
}

function requireExactKeys(value, allowed, name) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    fail('INVALID_INPUT', `${name} must be an object`);
  }
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) fail('INVALID_INPUT', `${name}.${key} is not allowed`);
  }
}

function requireUniqueIds(values, label) {
  if (new Set(values).size !== values.length) fail('DUPLICATE_ID', `${label} contains duplicates`);
}

function imageMagic(bytes, mimeType) {
  if (mimeType === 'image/png') {
    return bytes.length >= 8 && [137, 80, 78, 71, 13, 10, 26, 10]
      .every((byte, index) => bytes[index] === byte);
  }
  if (mimeType === 'image/jpeg') {
    return bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
  }
  if (mimeType === 'image/webp') {
    return bytes.length >= 12 && Buffer.from(bytes.subarray(0, 4)).toString('ascii') === 'RIFF'
      && Buffer.from(bytes.subarray(8, 12)).toString('ascii') === 'WEBP';
  }
  return false;
}

function digest(value) {
  return createHash('sha256').update(value).digest('hex');
}

/**
 * Produce a byte-verified *candidate* manifest. Nothing is persisted here.
 * A trusted storage coordinator must stage, fsync, verify placements, and
 * transactionally publish a committed snapshot before the UI says Preserved.
 * expectedPageCount and countEvidence MUST come from trusted runtime evidence,
 * not directly from an untrusted plugin or source claim.
 */
export function buildCaptureCandidate(input) {
  requireExactKeys(input, [
    'snapshotId', 'contentId', 'sectionId', 'capturedAt',
    'expectedPageCount', 'countEvidence', 'pages',
  ], 'input');
  const snapshotId = requireId(input.snapshotId, 'snapshotId');
  const contentId = requireId(input.contentId, 'contentId');
  const sectionId = requireId(input.sectionId, 'sectionId');
  if (typeof input.capturedAt !== 'string' || !/^\d{4}-\d{2}-\d{2}T/.test(input.capturedAt)
    || !Number.isFinite(Date.parse(input.capturedAt))) {
    fail('INVALID_INPUT', 'capturedAt must be an ISO timestamp');
  }
  if (input.countEvidence !== 'verified_source_count' && input.countEvidence !== 'unknown') {
    fail('INVALID_INPUT', 'invalid countEvidence');
  }
  const count = input.expectedPageCount;
  if (count !== null && (!Number.isSafeInteger(count) || count <= 0 || count > 100000)) {
    fail('INVALID_INPUT', 'expectedPageCount must be a bounded positive integer or null');
  }
  if (input.countEvidence === 'verified_source_count' && count === null) {
    fail('INVALID_INPUT', 'verified count evidence requires expectedPageCount');
  }
  if (!Array.isArray(input.pages) || input.pages.length > 100000) {
    fail('INVALID_INPUT', 'pages must be a bounded array');
  }
  const seenOrdinals = new Set();
  const seenUnits = new Set();
  const blobDigests = new Map();
  const pages = input.pages.map((page) => {
    requireExactKeys(page, ['ordinal', 'unitId', 'storageObjectId', 'mimeType', 'bytes'], 'page');
    const ordinal = page.ordinal;
    if (!Number.isSafeInteger(ordinal) || ordinal < 0 || ordinal >= 100000 || (count !== null && ordinal >= count)) {
      fail('INVALID_PAGE', 'page ordinal is out of range');
    }
    const unitId = requireId(page.unitId, 'page.unitId');
    const storageObjectId = requireId(page.storageObjectId, 'page.storageObjectId');
    if (seenOrdinals.has(ordinal) || seenUnits.has(unitId)) {
      fail('DUPLICATE_PAGE', 'page ordinal and unitId must be unique in one snapshot');
    }
    seenOrdinals.add(ordinal);
    seenUnits.add(unitId);
    if (!IMAGE_TYPES.has(page.mimeType)) fail('INVALID_IMAGE', 'unsupported image MIME type');
    if (!(page.bytes instanceof Uint8Array) || page.bytes.byteLength === 0
      || page.bytes.byteLength > MAX_IMAGE_BYTES || !imageMagic(page.bytes, page.mimeType)) {
      fail('INVALID_IMAGE', 'image bytes missing, oversized, or inconsistent with magic');
    }
    const sha256 = digest(page.bytes);
    if (blobDigests.has(storageObjectId) && blobDigests.get(storageObjectId) !== sha256) {
      fail('BLOB_ID_CONFLICT', 'storage object cannot represent differing bytes');
    }
    blobDigests.set(storageObjectId, sha256);
    return Object.freeze({
      ordinal,
      unitId,
      storageObjectId,
      mimeType: page.mimeType,
      byteLength: page.bytes.byteLength,
      sha256,
    });
  }).sort((a, b) => a.ordinal - b.ordinal);
  const missingOrdinals = [];
  if (count !== null) {
    for (let n = 0; n < count; n++) if (!seenOrdinals.has(n)) missingOrdinals.push(n);
  }
  const canCommitComplete = input.countEvidence === 'verified_source_count'
    && missingOrdinals.length === 0 && pages.length === count;
  const manifest = Object.freeze({
    schemaVersion: 1,
    snapshotId,
    contentId,
    sectionId,
    capturedAt: input.capturedAt,
    expectedPageCount: count,
    countEvidence: input.countEvidence,
    pages: Object.freeze(pages),
  });
  return Object.freeze({
    state: canCommitComplete ? 'complete_candidate' : 'partial_candidate',
    manifest,
    manifestSha256: digest(JSON.stringify(manifest)),
    missingOrdinals: Object.freeze(missingOrdinals),
  });
}

/**
 * Dry-run ONLY. Deletion requires independent approval, liveness rechecks,
 * locking, and a crash-safe journal in the trusted storage adapter.
 */
export function planSnapshotPrune(input) {
  requireExactKeys(input, [
    'storageObjectIds', 'snapshots', 'approvedPruneSnapshotIds', 'activeObjectIds',
  ], 'input');
  const storageObjectIds = input.storageObjectIds;
  const snapshots = input.snapshots;
  const approved = input.approvedPruneSnapshotIds ?? [];
  const activeObjectIds = input.activeObjectIds ?? [];
  if (!Array.isArray(storageObjectIds) || !Array.isArray(snapshots)
    || !Array.isArray(approved) || !Array.isArray(activeObjectIds)) {
    fail('INVALID_INPUT', 'storage, snapshot and approval collections must be arrays');
  }
  storageObjectIds.forEach(v => requireId(v, 'storageObjectId'));
  activeObjectIds.forEach(v => requireId(v, 'activeObjectId'));
  approved.forEach(v => requireId(v, 'approvedPruneSnapshotId'));
  requireUniqueIds(storageObjectIds, 'storageObjectIds');
  requireUniqueIds(approved, 'approvedPruneSnapshotIds');
  requireUniqueIds(activeObjectIds, 'activeObjectIds');
  const known = new Set(storageObjectIds);
  const active = new Set(activeObjectIds);
  for (const id of active) if (!known.has(id)) fail('MISSING_OBJECT', `active object ${id} not found`);
  const snapshotIds = [];
  const references = new Set();
  const removableReferences = new Set();
  const candidate = new Set(approved);
  for (const snapshot of snapshots) {
    requireExactKeys(snapshot, ['id', 'pinned', 'state', 'objectIds'], 'snapshot');
    const id = requireId(snapshot.id, 'snapshot.id');
    snapshotIds.push(id);
    if (typeof snapshot.pinned !== 'boolean'
      || !['committed', 'partial', 'staging'].includes(snapshot.state)
      || !Array.isArray(snapshot.objectIds)) fail('INVALID_INPUT', 'invalid snapshot state');
    if (candidate.has(id) && (snapshot.pinned || snapshot.state === 'staging')) {
      fail('PROTECTED_SNAPSHOT', `snapshot ${id} is pinned or staging`);
    }
    const seen = new Set();
    for (const objectId of snapshot.objectIds) {
      requireId(objectId, 'snapshot.objectId');
      if (!known.has(objectId)) fail('MISSING_OBJECT', `snapshot ${id} references missing object ${objectId}`);
      if (seen.has(objectId)) fail('DUPLICATE_ID', `snapshot ${id} repeats object ${objectId}`);
      seen.add(objectId);
      if (candidate.has(id)) removableReferences.add(objectId);
      else references.add(objectId);
    }
  }
  requireUniqueIds(snapshotIds, 'snapshotIds');
  for (const id of candidate) if (!snapshotIds.includes(id)) fail('UNKNOWN_SNAPSHOT', `unknown snapshot ${id}`);
  const reclaimableObjectIds = [...removableReferences]
    .filter(id => !references.has(id) && !active.has(id)).sort();
  return Object.freeze({
    approvedSnapshotIds: Object.freeze([...approved].sort()),
    reclaimableObjectIds: Object.freeze(reclaimableObjectIds),
    protectedObjectIds: Object.freeze([...new Set([...references, ...active])].sort()),
  });
}
