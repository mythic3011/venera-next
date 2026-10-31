// Linux trusted-host reference only. This is NOT the canonical v2 StorageWriter.
import { createHash, randomUUID } from 'node:crypto';
import { constants } from 'node:fs';
import { lstat, realpath, open, mkdir, link, unlink } from 'node:fs/promises';
import { resolve } from 'node:path';
import { buildCaptureCandidate } from './contract.mjs';

const MAX_PAGES = 128;
const MAX_TOTAL_BYTES = 128 * 1024 * 1024;
const MAX_MANIFEST_BYTES = 256 * 1024;
const SHA = /^[0-9a-f]{64}$/;
const ID = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const DIR_FLAGS = constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW;
const READ_FLAGS = constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK;
const WRITE_FLAGS = constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY | constants.O_NOFOLLOW;

function failure(code) { const error = new Error(code); error.code = code; throw error; }
function sha(bytes) { return createHash('sha256').update(bytes).digest('hex'); }
function fdpath(dir, key) { return '/proc/self/fd/' + dir.fd + '/' + key; }
function assertId(id) { if (typeof id !== 'string' || !ID.test(id)) failure('INVALID_ID'); }
async function requirePrivateRoot(root) {
  if (process.platform !== 'linux' || process.getuid?.() === undefined) failure('PLATFORM_UNSUPPORTED');
  if (typeof root !== 'string' || !root.startsWith('/') || root.includes('\0')) failure('ROOT_INVALID');
  const path = resolve(root);
  const stat = await lstat(path);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid()
    || (stat.mode & 0o077) !== 0 || await realpath(path) !== path) failure('ROOT_UNTRUSTED');
  return open(path, DIR_FLAGS);
}
async function privateChild(root, name) {
  try { await mkdir(fdpath(root, name), { mode: 0o700 }); }
  catch (err) { if (err.code !== 'EEXIST') throw err; }
  const handle = await open(fdpath(root, name), DIR_FLAGS);
  const stat = await handle.stat();
  const owner = await root.stat();
  if (!stat.isDirectory() || stat.uid !== process.getuid() || (stat.mode & 0o077) !== 0
    || stat.dev !== owner.dev) { await handle.close(); failure('DIRECTORY_UNTRUSTED'); }
  return handle;
}
async function readBounded(dir, key, maxBytes) {
  let handle;
  try { handle = await open(fdpath(dir, key), READ_FLAGS); }
  catch (err) { if (err.code === 'ENOENT') return null; throw err; }
  try {
    const stat = await handle.stat();
    if (!stat.isFile() || stat.size < 1 || stat.size > maxBytes) failure('STORED_OBJECT_INVALID');
    const bytes = await handle.readFile();
    const again = await handle.stat();
    if (bytes.length !== stat.size || again.dev !== stat.dev || again.ino !== stat.ino
      || again.size !== stat.size || again.mtimeMs !== stat.mtimeMs || again.ctimeMs !== stat.ctimeMs) {
      failure('STORED_OBJECT_CHANGED');
    }
    return bytes;
  } finally { await handle.close(); }
}
async function writeExclusive(dir, name, bytes) {
  let handle;
  try {
    handle = await open(fdpath(dir, name), WRITE_FLAGS, 0o600);
    await handle.writeFile(bytes);
    await handle.sync();
  } finally { await handle?.close(); }
  await dir.sync();
}
async function hardlinkExclusive(fromDir, fromName, toDir, toName) {
  try { await link(fdpath(fromDir, fromName), fdpath(toDir, toName)); }
  catch (err) { if (err.code !== 'EEXIST') throw err; return false; }
  await toDir.sync();
  return true;
}

/** Proof adapter. It must only be invoked by a trusted host, not a plugin or renderer. */
export async function openLocalPreservationProof({ privateRoot, checkpoint = async () => {} }) {
  if (typeof checkpoint !== 'function') failure('INVALID_CHECKPOINT');
  const root = await requirePrivateRoot(privateRoot);
  const handles = [root];
  let closed = false;
  let busy = false;
  try {
    const stage = await privateChild(root, '.stage'); handles.push(stage);
    const blobs = await privateChild(root, 'blobs'); handles.push(blobs);
    const manifests = await privateChild(root, 'manifests'); handles.push(manifests);
    const intents = await privateChild(root, 'intents'); handles.push(intents);
    await root.sync();
    const alive = () => { if (closed) failure('STORE_CLOSED'); };
    const loadManifest = async (snapshotId) => {
      assertId(snapshotId);
      const bytes = await readBounded(manifests, snapshotId + ".json", MAX_MANIFEST_BYTES);
      if (bytes === null) return null;
      let wrapper;
      try { wrapper = JSON.parse(bytes.toString('utf8')); } catch { failure('MANIFEST_INVALID'); }
      if (wrapper?.formatVersion !== 1 || !wrapper.manifest || !SHA.test(wrapper.manifestSha256)
        || sha(Buffer.from(JSON.stringify(wrapper.manifest))) !== wrapper.manifestSha256
        || wrapper.manifest.snapshotId !== snapshotId || !Array.isArray(wrapper.manifest.pages)
        || wrapper.manifest.pages.length > MAX_PAGES || wrapper.manifest.expectedPageCount !== wrapper.manifest.pages.length
        || wrapper.manifest.countEvidence !== 'verified_source_count') failure('MANIFEST_INVALID');
      const seen = new Set();
      for (const [i, page] of wrapper.manifest.pages.entries()) {
        if (page.ordinal !== i || !ID.test(page.unitId) || !ID.test(page.storageObjectId)
          || !SHA.test(page.sha256) || !Number.isSafeInteger(page.byteLength)
          || page.byteLength < 1 || page.byteLength > MAX_TOTAL_BYTES || seen.has(page.unitId)) failure('MANIFEST_INVALID');
        seen.add(page.unitId);
      }
      return wrapper;
    };
    async function writeCapture(input) {
      alive();
      if (busy) failure('WRITER_BUSY'); // only one writer per adapter instance; cross-process uses EXCL intent
      busy = true;
      try {
        const result = buildCaptureCandidate(input);
        if (result.state !== 'complete_candidate') failure('CAPTURE_NOT_COMPLETE');
        if (input.pages.length > MAX_PAGES || input.pages.reduce((sum, p) => sum + p.bytes.byteLength, 0) > MAX_TOTAL_BYTES) {
          failure('CAPTURE_OVER_BUDGET');
        }
        const id = result.manifest.snapshotId;
        const existing = await loadManifest(id);
        if (existing) {
          if (existing.manifestSha256 !== result.manifestSha256) failure('SNAPSHOT_ID_CONFLICT');
          // Verify every byte before accepting an idempotent replay.
          for (const page of existing.manifest.pages) await readVerifiedBlob(page);
          return { state: 'committed', snapshotId: id, replay: true };
        }
        const intentName = id + ".json";
        // EXCL means a previous crash or concurrent writer cannot be silently overwritten.
        try { await writeExclusive(intents, intentName, Buffer.from(JSON.stringify({
          snapshotId: id, manifestSha256: result.manifestSha256, phase: 'intent',
        }))); } catch (err) { if (err.code === 'EEXIST') failure('CAPTURE_PENDING_REVIEW'); throw err; }
        await checkpoint('intent_durable');
        for (const page of result.manifest.pages) {
          const bytes = input.pages.find(p => p.unitId === page.unitId)?.bytes;
          if (!(bytes instanceof Uint8Array) || bytes.length !== page.byteLength || sha(bytes) !== page.sha256) {
            failure('CAPTURE_BYTES_CHANGED');
          }
          const blobName = page.sha256 + ".blob";
          const already = await readBounded(blobs, blobName, MAX_TOTAL_BYTES);
          if (already !== null) {
            if (already.length !== page.byteLength || sha(already) !== page.sha256) failure('BLOB_CORRUPT');
            continue;
          }
          const tmp = randomUUID() + ".part";
          await writeExclusive(stage, tmp, bytes);
          const staged = await readBounded(stage, tmp, MAX_TOTAL_BYTES);
          if (!staged || sha(staged) !== page.sha256 || staged.length !== page.byteLength) failure('STAGE_CORRUPT');
          await checkpoint('page_staged');
          const created = await hardlinkExclusive(stage, tmp, blobs, blobName);
          if (!created) {
            const raced = await readBounded(blobs, blobName, MAX_TOTAL_BYTES);
            if (!raced || sha(raced) !== page.sha256 || raced.length !== page.byteLength) failure('BLOB_CORRUPT');
          }
          await unlink(fdpath(stage, tmp)); await stage.sync();
          await checkpoint('page_promoted');
        }
        // The manifest is the proof-store's visibility commit; NOT a v2 SQLite transaction.
        for (const page of result.manifest.pages) await readVerifiedBlob(page);
        await checkpoint('before_manifest_publish');
        const wrapper = Buffer.from(JSON.stringify({
          formatVersion: 1, manifestSha256: result.manifestSha256, manifest: result.manifest,
        }));
        if (wrapper.length > MAX_MANIFEST_BYTES) failure('MANIFEST_OVER_BUDGET');
        const tmp = randomUUID() + ".manifest";
        await writeExclusive(stage, tmp, wrapper);
        const published = await hardlinkExclusive(stage, tmp, manifests, id + ".json");
        if (!published) failure('SNAPSHOT_ID_CONFLICT');
        await unlink(fdpath(stage, tmp)); await stage.sync();
        await checkpoint('after_manifest_publish');
        await unlink(fdpath(intents, intentName)); await intents.sync();
        return { state: 'committed', snapshotId: id, replay: false };
      } finally { busy = false; }
    }
    async function readVerifiedBlob(page) {
      const bytes = await readBounded(blobs, page.sha256 + ".blob", MAX_TOTAL_BYTES);
      if (!bytes || bytes.length !== page.byteLength || sha(bytes) !== page.sha256) failure('PRESERVED_BYTES_UNAVAILABLE');
      return bytes;
    }
    async function readPreservedPage({ snapshotId, ordinal }) {
      alive();
      const snapshot = await loadManifest(snapshotId);
      if (!snapshot) failure('SNAPSHOT_NOT_FOUND');
      if (!Number.isSafeInteger(ordinal) || ordinal < 0 || ordinal >= snapshot.manifest.pages.length) failure('PAGE_NOT_FOUND');
      const page = snapshot.manifest.pages[ordinal];
      return { unitId: page.unitId, mimeType: page.mimeType, bytes: await readVerifiedBlob(page) };
    }
    async function auditSnapshot({ snapshotId }) {
      alive();
      assertId(snapshotId);
      const pending = (await readBounded(intents, snapshotId + ".json", MAX_MANIFEST_BYTES)) !== null;
      const snapshot = await loadManifest(snapshotId);
      if (!snapshot) return { snapshotId, status: pending ? 'uncommitted_review' : 'not_found' };
      try { for (const page of snapshot.manifest.pages) await readVerifiedBlob(page); }
      catch { return { snapshotId, status: 'committed_bytes_unavailable' }; }
      return { snapshotId, status: pending ? 'committed_pending_intent_review' : 'healthy' };
    }
    async function close() {
      if (closed) return;
      if (busy) failure('WRITER_BUSY');
      closed = true;
      await Promise.allSettled(handles.slice().reverse().map(h => h.close()));
    }
    return Object.freeze({ writeCapture, readPreservedPage, auditSnapshot, close });
  } catch (error) {
    await Promise.allSettled(handles.reverse().map(h => h.close()));
    throw error;
  }
}
