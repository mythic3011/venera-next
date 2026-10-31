import test from 'node:test';
import assert from 'node:assert/strict';
import { buildCaptureCandidate, planSnapshotPrune } from '../src/contract.mjs';

const png = () => Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10, 0]);
const jpeg = () => Uint8Array.from([255, 216, 255, 0]);
const page = (ordinal, unitId, bytes = png()) => ({
  ordinal, unitId, storageObjectId: `blob-${unitId}`,
  mimeType: 'image/png', bytes,
});
const capture = (overrides = {}) => ({
  snapshotId: 'snap-1', contentId: 'comic-1', sectionId: 'chapter-1',
  capturedAt: '2026-10-31T12:00:00Z', expectedPageCount: 2,
  countEvidence: 'verified_source_count', pages: [page(0, 'unit-1'), page(1, 'unit-2')],
  ...overrides,
});
const gc = (overrides = {}) => ({
  storageObjectIds: ['a', 'b', 'c'],
  snapshots: [
    { id: 's1', pinned: true, state: 'committed', objectIds: ['a', 'b'] },
    { id: 's2', pinned: false, state: 'committed', objectIds: ['b', 'c'] },
  ], approvedPruneSnapshotIds: [], activeObjectIds: [], ...overrides,
});

// Candidate creation is intentionally NOT a durable snapshot commit.
test('verified count + matching bytes/order produces a complete candidate', () => {
  const result = buildCaptureCandidate(capture());
  assert.equal(result.state, 'complete_candidate');
  assert.equal(result.missingOrdinals.length, 0);
  assert.match(result.manifestSha256, /^[a-f0-9]{64}$/);
  assert.match(result.manifest.pages[0].sha256, /^[a-f0-9]{64}$/);
  assert.ok(Object.isFrozen(result.manifest.pages));
});
test('stable manifest digest independent of acquisition order', () => {
  const input = capture();
  const a = buildCaptureCandidate(input);
  const b = buildCaptureCandidate({ ...input, pages: [...input.pages].reverse() });
  assert.equal(a.manifestSha256, b.manifestSha256);
});
test('changed image produces distinct immutable version evidence', () => {
  const one = buildCaptureCandidate(capture());
  const two = buildCaptureCandidate(capture({ pages: [page(0, 'unit-1'), page(1, 'unit-2', Uint8Array.from([...png(), 1]))] }));
  assert.notEqual(one.manifestSha256, two.manifestSha256);
  assert.notEqual(one.manifest.pages[1].sha256, two.manifest.pages[1].sha256);
  assert.equal(one.manifest.pages[1].byteLength, 9);
});
test('unknown trusted count cannot be complete', () => {
  const x = buildCaptureCandidate(capture({ expectedPageCount: null, countEvidence: 'unknown' }));
  assert.equal(x.state, 'partial_candidate');
});
test('unverified count cannot be complete even when page count matches', () => {
  assert.equal(buildCaptureCandidate(capture({ countEvidence: 'unknown' })).state, 'partial_candidate');
});
test('missing page yields explicit partial and gap', () => {
  const x = buildCaptureCandidate(capture({ pages: [page(1, 'unit-2')] }));
  assert.equal(x.state, 'partial_candidate');
  assert.deepEqual(x.missingOrdinals, [0]);
});
test('invalid image magic, MIME and zero-length input reject', () => {
  assert.throws(() => buildCaptureCandidate(capture({ pages: [page(0, 'unit-1', jpeg())] })), { code: 'INVALID_IMAGE' });
  assert.throws(() => buildCaptureCandidate(capture({ pages: [{ ...page(0, 'unit-1'), mimeType: 'text/html' }] })), { code: 'INVALID_IMAGE' });
  assert.throws(() => buildCaptureCandidate(capture({ pages: [page(0, 'unit-1', new Uint8Array(0))] })), { code: 'INVALID_IMAGE' });
});
test('duplicate ordinal or unit ID rejected; out-of-range page rejected', () => {
  assert.throws(() => buildCaptureCandidate(capture({ pages: [page(0, 'u1'), page(0, 'u2')] })), { code: 'DUPLICATE_PAGE' });
  assert.throws(() => buildCaptureCandidate(capture({ pages: [page(0, 'u1'), page(1, 'u1')] })), { code: 'DUPLICATE_PAGE' });
  assert.throws(() => buildCaptureCandidate(capture({ pages: [page(2, 'u2')] })), { code: 'INVALID_PAGE' });
});
test('forbidden raw URLs and secrets are rejected from manifest input', () => {
  assert.throws(() => buildCaptureCandidate({ ...capture(), sourceUrl: 'https://example.com' }), { code: 'INVALID_INPUT' });
  assert.throws(() => buildCaptureCandidate(capture({ pages: [{ ...page(0, 'unit-1'), cookie: 'secret' }] })), { code: 'INVALID_INPUT' });
});
test('verified count without expected count rejected', () => {
  assert.throws(() => buildCaptureCandidate(capture({ expectedPageCount: null })), { code: 'INVALID_INPUT' });
});
test('pinned snapshot cannot be pruned', () => {
  assert.throws(() => planSnapshotPrune(gc({ approvedPruneSnapshotIds: ['s1'] })), { code: 'PROTECTED_SNAPSHOT' });
});
test('unpinned snapshot prune reclaims only unshared objects', () => {
  const p = planSnapshotPrune(gc({ approvedPruneSnapshotIds: ['s2'] }));
  assert.deepEqual(p.reclaimableObjectIds, ['c']);
  assert.deepEqual(p.protectedObjectIds, ['a', 'b']);
});
test('active capture/restore lease protects a would-be reclaimed object', () => {
  const p = planSnapshotPrune(gc({ approvedPruneSnapshotIds: ['s2'], activeObjectIds: ['c'] }));
  assert.deepEqual(p.reclaimableObjectIds, []);
});
test('unapproved snapshot cannot be collected even if unpinned', () => {
  assert.deepEqual(planSnapshotPrune(gc()).reclaimableObjectIds, []);
});
test('staging snapshot cannot be pruned', () => {
  assert.throws(() => planSnapshotPrune(gc({
    snapshots: [{ id: 's1', pinned: false, state: 'staging', objectIds: ['a'] }],
    approvedPruneSnapshotIds: ['s1'],
  })), { code: 'PROTECTED_SNAPSHOT' });
});
test('missing referenced blob and unknown prune approval fail closed', () => {
  assert.throws(() => planSnapshotPrune(gc({ storageObjectIds: ['a', 'c'] })), { code: 'MISSING_OBJECT' });
  assert.throws(() => planSnapshotPrune(gc({ approvedPruneSnapshotIds: ['nonexistent'] })), { code: 'UNKNOWN_SNAPSHOT' });
});
test('orphan bytes are not silently reclaimed by a snapshot prune', () => {
  const p = planSnapshotPrune(gc({ storageObjectIds: ['a', 'b', 'c', 'orphan'], approvedPruneSnapshotIds: ['s2'] }));
  assert.deepEqual(p.reclaimableObjectIds, ['c']);
});
test('duplicate storage identities and duplicate snapshot identities fail closed', () => {
  assert.throws(() => planSnapshotPrune(gc({ storageObjectIds: ['a', 'a'] })), { code: 'DUPLICATE_ID' });
  assert.throws(() => planSnapshotPrune(gc({ snapshots: [gc().snapshots[0], gc().snapshots[0]] })), { code: 'DUPLICATE_ID' });
});
test('identical storage object ID cannot claim two different image hashes', () => {
  const second = { ...page(1, 'unit-2', Uint8Array.from([...png(), 1])), storageObjectId: 'blob-unit-1' };
  assert.throws(() => buildCaptureCandidate(capture({ pages: [page(0, 'unit-1'), second] })), { code: 'BLOB_ID_CONFLICT' });
});
