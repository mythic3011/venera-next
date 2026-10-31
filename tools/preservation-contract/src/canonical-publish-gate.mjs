// Trusted-host integration seam only; NOT an installed canonical v2 adapter.
// No raw DB access, source network calls, or untrusted plugin callbacks.
import { createHash } from 'node:crypto';

const ID = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const SHA = /^[a-f0-9]{64}$/;
const MAX_PAGES = 128;
function deny(code) { const error = new Error(code); error.code = code; throw error; }
function validId(value) { return typeof value === 'string' && ID.test(value); }
function hash(value) { return createHash('sha256').update(value).digest('hex'); }
function assertPorts(store, canonical, placements) {
  if (typeof store?.auditSnapshot !== 'function' ||
      typeof store?.readCommittedManifest !== 'function' ||
      typeof store?.readPreservedPage !== 'function' ||
      typeof canonical?.readSectionOrder !== 'function' ||
      typeof canonical?.commitPreservationBinding !== 'function' ||
      typeof placements?.verifyReadablePlacement !== 'function') deny('TRUSTED_PORT_UNAVAILABLE');
}
export function fingerprintCanonicalOrder({ contentId, sectionId, units }) {
  if (!validId(contentId) || !validId(sectionId) ||
      !Array.isArray(units) || units.length < 1 || units.length > MAX_PAGES) deny('CANONICAL_ORDER_INVALID');
  const ids = new Set();
  const indices = new Set();
  for (const unit of units) {
    if (!unit || !validId(unit.id) || !Number.isSafeInteger(unit.unitIndex) || unit.unitIndex < 0 ||
      ids.has(unit.id) || indices.has(unit.unitIndex)) deny('CANONICAL_ORDER_INVALID');
    ids.add(unit.id);
    indices.add(unit.unitIndex);
  }
  // Active reader ordering may differ from source unitIndex; array order is authority.
  return hash(JSON.stringify({
    formatVersion: 1, contentId, sectionId,
    units: units.map(u => [u.id, u.unitIndex]),
  }));
}

/**
 * A verified standalone proof store can supply immutable page bytes, but ONLY
 * the future host-owned canonical port may attach a snapshot to content.
 *
 * commitPreservationBinding MUST atomically recheck:
 *   - current content/section and exact active-order fingerprint
 *   - owner scope, snapshotId uniqueness/idempotency, and manifest hash
 *   - per-unit StorageObject identity, readable placement and byte evidence
 *   - pin/retention roots, then write binding + reference edges in one transaction.
 * If any check changes, it MUST reject and roll back. Returning success without
 * these rules violates the trusted port contract; this module cannot prove DB
 * transactions by inspecting a callback's return value.
 */
export async function publishPreservedSnapshot({
  store, canonical, placements, ownerScopeId, snapshotId,
}) {
  assertPorts(store, canonical, placements);
  if (!validId(ownerScopeId) || !validId(snapshotId)) deny('PUBLISH_INPUT_INVALID');
  const status = await store.auditSnapshot({ snapshotId });
  if (status?.status !== 'healthy') deny('PRESERVATION_PROOF_UNHEALTHY');
  const wrapper = await store.readCommittedManifest({ snapshotId });
  if (wrapper?.formatVersion !== 1 || !SHA.test(wrapper.manifestSha256) ||
      !wrapper.manifest || wrapper.manifest.snapshotId !== snapshotId ||
      hash(JSON.stringify(wrapper.manifest)) !== wrapper.manifestSha256) deny('PRESERVATION_MANIFEST_INVALID');
  const manifest = wrapper.manifest;
  if (!validId(manifest.contentId) || !validId(manifest.sectionId) ||
      manifest.countEvidence !== 'verified_source_count' ||
      !Array.isArray(manifest.pages) || manifest.pages.length < 1 ||
      manifest.pages.length > MAX_PAGES ||
      manifest.expectedPageCount !== manifest.pages.length) deny('PRESERVATION_MANIFEST_INVALID');

  // Current canonical reader order is consulted, never reconstituted from URLs or filenames.
  const current = await canonical.readSectionOrder({
    ownerScopeId, contentId: manifest.contentId, sectionId: manifest.sectionId,
  });
  if (!current || !Array.isArray(current.units)) deny('CANONICAL_ORDER_UNAVAILABLE');
  const orderDigest = fingerprintCanonicalOrder({
    contentId: manifest.contentId, sectionId: manifest.sectionId, units: current.units,
  });
  if (current.units.length !== manifest.pages.length) deny('CANONICAL_ORDER_CHANGED');
  const links = [];
  const seenBlobIds = new Map();
  for (let index = 0; index < manifest.pages.length; index++) {
    const page = manifest.pages[index];
    const canonicalUnit = current.units[index];
    if (page?.ordinal !== index || page.unitId !== canonicalUnit.id ||
        !validId(page.storageObjectId) || !SHA.test(page.sha256) ||
        !Number.isSafeInteger(page.byteLength) || page.byteLength < 1 ||
        page.byteLength > 32 * 1024 * 1024) deny('CANONICAL_PAGE_BINDING_MISMATCH');

    const previous = seenBlobIds.get(page.storageObjectId);
    if (previous !== undefined && previous !== page.sha256) deny('CANONICAL_STORAGE_ID_CONFLICT');
    seenBlobIds.set(page.storageObjectId, page.sha256);

    // Recheck the actual owned proof bytes before asking the canonical storage authority.
    const saved = await store.readPreservedPage({ snapshotId, ordinal: index });
    if (saved.unitId !== page.unitId || saved.mimeType !== page.mimeType ||
        !(saved.bytes instanceof Uint8Array) ||
        saved.bytes.length !== page.byteLength || hash(saved.bytes) !== page.sha256) {
      deny('PRESERVATION_BYTES_CHANGED');
    }
    const placement = await placements.verifyReadablePlacement({
      ownerScopeId,
      storageObjectId: page.storageObjectId,
      expectedSha256: page.sha256,
      expectedBytes: page.byteLength,
    });
    if (placement?.verified !== true || !validId(placement.placementId) ||
        placement.storageObjectId !== page.storageObjectId ||
        placement.sha256 !== page.sha256 || placement.byteLength !== page.byteLength) {
      deny('CANONICAL_PLACEMENT_UNVERIFIED');
    }
    links.push(Object.freeze({
      unitId: page.unitId,
      ordinal: index,
      storageObjectId: page.storageObjectId,
      placementId: placement.placementId,
      sha256: page.sha256,
      byteLength: page.byteLength,
    }));
  }
  const input = Object.freeze({
    ownerScopeId,
    snapshotId,
    contentId: manifest.contentId,
    sectionId: manifest.sectionId,
    manifestSha256: wrapper.manifestSha256,
    expectedOrderDigest: orderDigest,
    links: Object.freeze(links),
  });
  const receipt = await canonical.commitPreservationBinding(input);
  if (receipt?.state !== 'committed' && receipt?.state !== 'replayed') deny('CANONICAL_COMMIT_UNCONFIRMED');
  if (receipt.snapshotId !== snapshotId || receipt.manifestSha256 !== wrapper.manifestSha256) {
    deny('CANONICAL_COMMIT_RECEIPT_INVALID');
  }
  return Object.freeze({
    snapshotId, state: receipt.state,
    manifestSha256: wrapper.manifestSha256,
    linkedPages: links.length,
  });
}
