import test from 'node:test';
import assert from 'node:assert/strict';
import { planBackupMediaInventory } from '../src/backup-contract.mjs';

const sample = (overrides = {}) => ({
  mode: 'full',
  selectedSnapshotIds: ['first', 'second'],
  verifiedObjectIds: ['a', 'b', 'c'],
  snapshots: [
    { id: 'first', state: 'committed', objectIds: ['a', 'b'] },
    { id: 'second', state: 'committed', objectIds: ['b', 'c'] },
  ],
  ...overrides,
});

test('full backup plans unique closure of all selected media dependencies', () => {
  const p = planBackupMediaInventory(sample());
  assert.deepEqual(p.mediaObjectIdsToTransfer, ['a', 'b', 'c']);
  assert.equal(p.completeMediaCandidate, true);
  assert.deepEqual(p.mediaObjectIdsNotIncluded, []);
});
test('full backup rejects unavailable required media, even if metadata exists', () => {
  assert.throws(() => planBackupMediaInventory(sample({ verifiedObjectIds: ['a', 'c'] })), { code: 'MEDIA_UNAVAILABLE' });
});
test('standard backup never claims media preservation', () => {
  const p = planBackupMediaInventory(sample({ mode: 'standard', verifiedObjectIds: [] }));
  assert.deepEqual(p.mediaObjectIdsToTransfer, []);
  assert.deepEqual(p.mediaObjectIdsNotIncluded, ['a', 'b', 'c']);
  assert.equal(p.completeMediaCandidate, false);
});
test('partial or staging snapshots are not eligible for complete-media inventory', () => {
  for (const state of ['partial', 'staging']) {
    assert.throws(() => planBackupMediaInventory(sample({ snapshots: [
      { id: 'first', state, objectIds: ['a'] },
      { id: 'second', state: 'committed', objectIds: ['b'] },
    ] })), { code: 'NOT_COMMITTED' });
  }
});
test('explicit selection reports omitted snapshots and shared objects once', () => {
  const p = planBackupMediaInventory(sample({ selectedSnapshotIds: ['first'] }));
  assert.deepEqual(p.omittedSnapshotIds, ['second']);
  assert.deepEqual(p.mediaObjectIdsToTransfer, ['a', 'b']);
});
test('unknown selected snapshot and duplicate identities are rejected', () => {
  assert.throws(() => planBackupMediaInventory(sample({ selectedSnapshotIds: ['unknown'] })), { code: 'UNKNOWN_SNAPSHOT' });
  assert.throws(() => planBackupMediaInventory(sample({ verifiedObjectIds: ['a', 'a'] })), { code: 'DUPLICATE_ID' });
});
test('unknown fields cannot carry credentials or URLs into inventory', () => {
  assert.throws(() => planBackupMediaInventory({ ...sample(), oauthToken: 'do-not-leak' }), { code: 'INVALID_INPUT' });
});
