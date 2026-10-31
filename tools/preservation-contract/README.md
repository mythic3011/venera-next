# Preservation Contract Harness (Prototype, not runtime)

Small, dependency-free Node.js reference harness for [self-hosted comic preservation + backup RFC](../../docs/plans/2026-10-31-self-hosted-comic-preservation-backup-rfc.md).

Run: `node --test tools/preservation-contract/test/*.test.mjs` from the repository root (Node >=20).

**Provides:** `buildCaptureCandidate` verifies byte hashes and basic image magic, validates canonical ordering, emits a deterministic candidate manifest hash, and only labels a snapshot *complete_candidate* with trusted external count evidence and full contiguous pages. `planSnapshotPrune` is a dry-run: it refuses to prune pinned or staging snapshots, retains shared blobs and active leases, and requires explicit snapshot-level prune approval. Tests include negative/fail-closed cases.

**Does not provide:** durable storage writes, SQLite transactions, a journal, true image decoding, transport security, source-level trust proof, snapshot commit authority, cloud encryption, Google Drive/S3 adapters, automatic capture, or user-facing restore. Its `verified_source_count` is a **trusted-host input contract**, not proof that a source accurately reports its total pages. A backend could lie or serve inconsistent pages; implementation must revalidate count/order/validators and record uncertainty.

**Non-authority:** This standalone test harness is not a `runtime/core` dependency, not an approved canonical v2 schema, and not a substitute for adopting PR #6's security contracts. Production use requires reviewed ownership, a private staged-byte writer, durable placement proofs, a transactional commit journal, and live GC locks plus a second liveness check immediately before deletion.
