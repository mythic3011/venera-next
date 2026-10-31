import test from 'node:test';
import assert from 'node:assert/strict';
import { readPageWithPreservation } from '../src/reader-fallback-proof.mjs';

const data = Uint8Array.from([137,80,78,71,13,10,26,10]);
const unavailable = Object.assign(new Error('gone'), { code: 'SNAPSHOT_NOT_FOUND' });
const corrupt = Object.assign(new Error('corrupt'), { code: 'PRESERVED_BYTES_UNAVAILABLE' });

test('preserved bytes win, even when original remote is deleted/unavailable', async () => {
  let remoteCalls=0;
  const result=await readPageWithPreservation({
    store:{ readPreservedPage:async () => ({unitId:'unit-1', bytes:data, mimeType:'image/png'}) },
    snapshotId:'version-1', ordinal:0,
    remoteRead:async () => { remoteCalls++; throw new Error('HTTP 404'); },
  });
  assert.equal(result.origin,'preserved');
  assert.equal(remoteCalls,0);
  assert.equal(result.unitId,'unit-1');
});

test('only missing snapshot allows remote fallback, with unverified source label', async () => {
  let requests=0;
  const r=await readPageWithPreservation({
    store:{ readPreservedPage:async () => {throw unavailable;} },
    snapshotId:'missing', ordinal:2,
    remoteRead:async ctx => {requests++; assert.deepEqual(ctx,{snapshotId:'missing',ordinal:2}); return {bytes:data};},
  });
  assert.equal(requests,1);
  assert.equal(r.origin,'remote_unverified');
});

test('corrupt preserved storage does not silently downgrade to remote bytes', async () => {
  let calls=0;
  await assert.rejects(readPageWithPreservation({
    store:{ readPreservedPage:async () => {throw corrupt;} },
    snapshotId:'version-1', ordinal:0,
    remoteRead:async () => {calls++; return {bytes:data};},
  }), { code:'PRESERVED_BYTES_UNAVAILABLE' });
  assert.equal(calls,0);
});

test('missing snapshot and remote HTTP 404 retains source error', async () => {
  await assert.rejects(readPageWithPreservation({
    store:{ readPreservedPage:async () => {throw unavailable;} },
    snapshotId:'missing', ordinal:0,
    remoteRead:async () => { throw Object.assign(new Error('HTTP 404'),{code:'HTTP_NOT_FOUND'}); },
  }), { code:'HTTP_NOT_FOUND' });
});
