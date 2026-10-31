/**
 * Proof-only reader selection. Not wired into canonical ReaderOpenTargetResolver.
 * Local bytes are independently verified by the proof store before return.
 * Only absence permits remote fallback; corruption cannot silently downgrade.
 */
export async function readPageWithPreservation({ store, snapshotId, ordinal, remoteRead, policy = 'prefer_preserved' }) {
  if (!store || typeof store.readPreservedPage !== 'function'
    || typeof remoteRead !== 'function') {
    throw new TypeError('trusted store and remoteRead callback are required');
  }
  if (policy !== 'prefer_preserved' && policy !== 'preserved_only') {
    throw new TypeError('invalid preservation policy');
  }
  try {
    const page = await store.readPreservedPage({ snapshotId, ordinal });
    return Object.freeze({ ...page, origin: 'preserved' });
  } catch (error) {
    if (error?.code !== 'SNAPSHOT_NOT_FOUND' || policy === 'preserved_only') throw error;
    // Caller/runtime owns source auth, policy, and network execution.
    // Never map fetched bytes to an old canonical unitId without validation.
    const remote = await remoteRead({ snapshotId, ordinal });
    if (!remote || !(remote.bytes instanceof Uint8Array)) {
      throw new TypeError('remote reader returned no valid bytes');
    }
    return Object.freeze({ ...remote, origin: 'remote_unverified' });
  }
}
