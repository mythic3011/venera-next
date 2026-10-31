import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, chmod, readFile, readdir, writeFile, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openLocalPreservationProof } from '../src/durable-proof.mjs';

const png = (suffix) => Uint8Array.from([137,80,78,71,13,10,26,10,...suffix]);
const input = (id='one') => ({
  snapshotId: id, contentId:'work-1', sectionId:'chapter-1', capturedAt:'2026-10-31T12:00:00Z',
  expectedPageCount: 2, countEvidence: 'verified_source_count',
  pages: [
    { ordinal:0, unitId:'unit-1', storageObjectId:'object-1', mimeType:'image/png', bytes:png([1,2]) },
    { ordinal:1, unitId:'unit-2', storageObjectId:'object-2', mimeType:'image/png', bytes:png([2,3]) },
  ],
});
async function fixture(fn) {
  const root = await mkdtemp(join(tmpdir(), 'venera-proof-'));
  await chmod(root, 0o700);
  try { await fn(root); } finally { await rm(root, { recursive: true, force: true }); }
}

test('durable manifest survives reopening and supplies offline page after remote fails', async () => fixture(async root => {
  let store = await openLocalPreservationProof({privateRoot:root});
  const r = await store.writeCapture(input());
  assert.deepEqual(r, {state:'committed', snapshotId:'one', replay:false});
  await store.close();
  // Simulate source 404: no network, no provider callbacks, only verified saved bytes.
  store = await openLocalPreservationProof({privateRoot:root});
  assert.equal((await store.auditSnapshot({snapshotId:'one'})).status, 'healthy');
  const page = await store.readPreservedPage({snapshotId:'one',ordinal:1});
  assert.equal(page.unitId,'unit-2');
  assert.deepEqual(page.bytes,Buffer.from(png([2,3])));
  await store.close();
}));

test('same capture is idempotent and immutable; changed page cannot reuse snapshot ID', async () => fixture(async root => {
  const store = await openLocalPreservationProof({privateRoot:root});
  await store.writeCapture(input());
  assert.equal((await store.writeCapture(input())).replay, true);
  const updated = input(); updated.pages[1].bytes = png([9,9]);
  await assert.rejects(store.writeCapture(updated), { code:'SNAPSHOT_ID_CONFLICT' });
  await store.close();
}));

test('shared page blob deduplicates across immutable snapshot versions', async () => fixture(async root => {
  const store = await openLocalPreservationProof({privateRoot:root});
  await store.writeCapture(input('v1'));
  const changed = input('v2'); changed.pages[1].bytes = png([9,9]);
  await store.writeCapture(changed);
  assert.equal((await readdir(join(root,'blobs'))).length,3);
  assert.deepEqual((await store.readPreservedPage({snapshotId:'v1',ordinal:1})).bytes,Buffer.from(png([2,3])));
  assert.deepEqual((await store.readPreservedPage({snapshotId:'v2',ordinal:1})).bytes,Buffer.from(png([9,9])));
  await store.close();
}));

test('crash after intent: no published snapshot and recovery remains review-only', async () => fixture(async root => {
  let store = await openLocalPreservationProof({privateRoot:root,checkpoint: async phase => {
    if (phase === 'intent_durable') throw new Error('simulated crash');
  }});
  await assert.rejects(store.writeCapture(input()), /simulated crash/);
  await store.close();
  store = await openLocalPreservationProof({privateRoot:root});
  assert.equal((await store.auditSnapshot({snapshotId:'one'})).status,'uncommitted_review');
  await assert.rejects(store.readPreservedPage({snapshotId:'one',ordinal:0}), {code:'SNAPSHOT_NOT_FOUND'});
  await assert.rejects(store.writeCapture(input()), {code:'CAPTURE_PENDING_REVIEW'});
  await store.close();
}));

test('crash after page promotion: uncommitted object cannot be read as preserved', async () => fixture(async root => {
  const store = await openLocalPreservationProof({privateRoot:root,checkpoint: async phase => {
    if (phase === 'page_promoted') throw new Error('simulated crash');
  }});
  await assert.rejects(store.writeCapture(input()), /simulated crash/);
  assert.equal((await store.auditSnapshot({snapshotId:'one'})).status,'uncommitted_review');
  await assert.rejects(store.readPreservedPage({snapshotId:'one',ordinal:0}), {code:'SNAPSHOT_NOT_FOUND'});
  await store.close();
}));

test('crash after manifest publication: committed snapshot readable but intent requires review', async () => fixture(async root => {
  let store = await openLocalPreservationProof({privateRoot:root,checkpoint: async phase => {
    if (phase === 'after_manifest_publish') throw new Error('simulated crash');
  }});
  await assert.rejects(store.writeCapture(input()), /simulated crash/);
  await store.close();
  store = await openLocalPreservationProof({privateRoot:root});
  assert.equal((await store.auditSnapshot({snapshotId:'one'})).status,'committed_pending_intent_review');
  assert.deepEqual((await store.readPreservedPage({snapshotId:'one',ordinal:0})).bytes,Buffer.from(png([1,2])));
  await store.close();
}));

test('tampered or missing stored page is not treated as a preserved read', async () => fixture(async root => {
  const store = await openLocalPreservationProof({privateRoot:root});
  await store.writeCapture(input());
  const names = await readdir(join(root,'blobs'));
  await writeFile(join(root,'blobs',names[0]), png([5,5]));
  const audit = await store.auditSnapshot({snapshotId:'one'});
  assert.equal(audit.status,'committed_bytes_unavailable');
  let failures=0;
  for(const ordinal of [0,1]) {
    try { await store.readPreservedPage({snapshotId:'one', ordinal}); }
    catch(e){ assert.equal(e.code,'PRESERVED_BYTES_UNAVAILABLE'); failures++; }
  }
  assert.equal(failures,1);
  await store.close();
}));

test('manifest tampering refuses offline read even when bytes exist', async () => fixture(async root => {
  const store = await openLocalPreservationProof({privateRoot:root});
  await store.writeCapture(input());
  const file=join(root,'manifests','one.json');
  const data=JSON.parse(await readFile(file,'utf8'));
  data.manifest.pages[0].ordinal=7;
  await writeFile(file,JSON.stringify(data));
  await assert.rejects(store.readPreservedPage({snapshotId:'one',ordinal:0}), {code:'MANIFEST_INVALID'});
  await store.close();
}));

test('private root, symlink stage and unsafe IDs rejected', async () => fixture(async root => {
  await chmod(root,0o755);
  await assert.rejects(openLocalPreservationProof({privateRoot:root}), {code:'ROOT_UNTRUSTED'});
  await chmod(root,0o700);
  await symlink('/tmp',join(root,'.stage'));
  await assert.rejects(openLocalPreservationProof({privateRoot:root}), e => ['ELOOP','ENOTDIR'].includes(e.code));
}));

test('partial/unknown count cannot be persisted as complete snapshot', async () => fixture(async root => {
  const store = await openLocalPreservationProof({privateRoot:root});
  const incomplete=input(); incomplete.pages.pop();
  await assert.rejects(store.writeCapture(incomplete), {code:'CAPTURE_NOT_COMPLETE'});
  const unknown=input(); unknown.countEvidence='unknown';
  await assert.rejects(store.writeCapture(unknown), {code:'CAPTURE_NOT_COMPLETE'});
  assert.equal((await readdir(join(root,'manifests'))).length,0);
  await store.close();
}));
