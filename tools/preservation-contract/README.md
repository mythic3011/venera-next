# Preservation Contract + Local Durability Proof (Prototype)

Standalone Node.js harness for the [self-hosted comic preservation and backup RFC](../../docs/plans/2026-10-31-self-hosted-comic-preservation-backup-rfc.md). **Not** imported by `runtime/core`, unmerged `runtime/v2`, or Flutter. It does **not** change the canonical design authority, app database, or production UI.

## Run

Requires Node.js >=22.16 on Linux for the local filesystem proof; the pure contract tests can run on other supported Node platforms.

```bash
node --test tools/preservation-contract/test/*.test.mjs
```

The pull request also adds a focused GitHub Actions workflow. Passing these tests establishes local reference behavior only, not a shipping backup service.

## Surfaces and guarantees

| Surface | Provides | Does not provide |
| --- | --- | --- |
| `buildCaptureCandidate` | Ordered SHA-256 page manifest; image magic and bounded page validation; partial vs complete **candidate** | Provider truth, pixel decode, authenticated provenance, durable storage |
| `planSnapshotPrune` | Non-mutating, consent-scoped, pin/shared-object/lease-aware GC plan | Live lock, durable graph refcounts, actual deletion |
| `planBackupMediaInventory` | Full media dependency closure; Standard visibly excludes bytes; Full refuses missing media | Encrypted, uploaded or restorable backup |
| `openLocalPreservationProof` | **Linux-only trusted-host reference**: owner-private root check, no-follow directory access, 0600 exclusive staged files, fsync, exclusive blob promotion, hash-verified immutable manifest publication, proof-store offline reads, read-only crash audit | v2 SQLite transactions, StoragePlacement/Unit linking, real provider, app UI, authenticated media backup, cloud transport |

## Local filesystem demonstration

The caller creates and owns a **new existing** `0700` private directory. The trusted host calls:

```js
import { openLocalPreservationProof } from './src/durable-proof.mjs';

const store = await openLocalPreservationProof({ privateRoot: '/absolute/private/0700/path' });
// writeCapture accepts the buildCaptureCandidate input shape, with trusted count evidence.
// The callback is NOT available to an untrusted plugin or UI.
await store.writeCapture(captureInput);
const result = await store.readPreservedPage({ snapshotId: captureInput.snapshotId, ordinal: 0 });
await store.close();
```

A complete candidate becomes **committed within this proof store only** after the verified blobs and manifest reach the local filesystem; it is **not** a committed v2 canonical Snapshot or readable StoragePlacement. The local manifest is the proof-store visibility boundary; no cross-filesystem SQLite atomicity is claimed. The source is never recontacted by `readPreservedPage`.

Crash checkpoints used by tests:

```text
intent_durable -> page_staged -> page_promoted
  -> before_manifest_publish -> after_manifest_publish
```

A crash **before** manifest publish leaves an uncommitted intent and staged/promoted bytes for review, with no offline snapshot claim. A crash **after** publish leaves a readable manifest and a pending intent until reviewed. No automatic deletion, repair or GC is performed. Replay is permitted only for an already published matching manifest whose referenced bytes still verify.

## Security and integration boundaries

- `openLocalPreservationProof` is a Linux host-only proof using `/proc/self/fd` and `O_NOFOLLOW`, not a plugin-facing API. `privateRoot`, `captureInput`, and failpoints must be supplied by a trusted host. **No OS-grant, user-gesture authority, or multi-process writer lock is implemented**; the exclusive intent guards snapshot-ID collisions, not every external same-UID race.
- Source count evidence is passed as a trusted input contract. The code cannot establish that an upstream provider supplied every page. Basic image magic is not full decode or malicious-image analysis.
- SHA-256 manifest checks provide self-consistency against accidental corruption. A host attacker who can rewrite both manifest and hash is outside this proof's integrity protection; future backup envelopes require authenticated integrity and independent recovery material.
- Local blob files are not encrypted, signed, or replicated. Loss of this filesystem still destroys the proof data.
- Production integration must reconcile with [draft PR #6](https://github.com/mythic3011/venera-next/pull/6)'s greenfield v2 `StorageObject` writer, explicit trusted media grants, canonical `StoragePlacement`, journal recovery, and reader `ContentUnit` identity. Do **not** copy this proof's file-metadata authority into a second production storage subsystem.
- No live LANraragi / Komga / Kavita API calls, Google Drive/S3 backups, real encrypted restore or end-user snapshot preservation have been implemented.

## Test categories

The test suite covers candidate validation, immutable revision hashing, shared bytes, GC pin guards, Full-vs-Standard inventory safety, durable replay across reopen, source-independent offline page retrieval, crash checkpoint boundaries, corrupted page/manifest rejection, root permission/symlink denial and incomplete capture rejection.
