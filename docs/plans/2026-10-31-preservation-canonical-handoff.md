# Handoff: Canonical V2 Preservation Attachment

> **Status: integration contract / proposed APIs.** PR #7 contains an independent proof-store plus a host-port publication gate. PR #6's unmerged `runtime/v2/src/host-sqlite.mjs` and `storage-writer-linux.mjs` currently **do not** expose the read/attach/placement ports below. No current end-user Venera runtime can complete this handoff. Do not paste a second SQLite authority or import the deprecated `runtime/core` to make it appear complete.

## Why a separate attach transaction is required

The proof store can retain historical bytes independently of an origin source, but the new v2 storage writer in [PR #6](https://github.com/mythic3011/venera-next/pull/6) deliberately creates **detached** `StorageObject + StoragePlacement` records under an explicitly authorized `storage_object_only` operation. It does *not* authorize setting `content_units.storage_object_id`, creating preservation versions, or silently reusing legacy import consent.

The attachment must be its **own approved domain use case**, with separate trusted user consent (or scoped prior opt-in to preserve this chapter), ownership, source provenance, and a serialized transactional write.

## Required ports (not implemented in PR #6)

```ts
interface CanonicalPreservationPorts {
  readSectionOrder(input: {
    ownerScopeId: string;
    contentId: string;
    sectionId: string;
  }): Promise<{
    units: readonly { id: string; unitIndex: number }[]; // canonical DISPLAY order
  }>;

  commitPreservationBinding(input: {
    ownerScopeId: string;
    snapshotId: string;
    contentId: string;
    sectionId: string;
    manifestSha256: string;
    expectedOrderDigest: string;
    links: readonly {
      unitId: string;
      ordinal: number;
      storageObjectId: string;
      placementId: string;
      sha256: string;
      byteLength: number;
    }[];
  }): Promise<{
    state: "committed" | "replayed";
    snapshotId: string;
    manifestSha256: string;
  }>;
}

interface VerifiedPlacementPort {
  verifyReadablePlacement(input: {
    ownerScopeId: string;
    storageObjectId: string;
    expectedSha256: string;
    expectedBytes: number;
  }): Promise<{
    verified: true;
    ownerScopeId: string;
    placementId: string;
    role: "authority" | "mirror";
    syncStatus: "synced";
    storageObjectId: string;
    sha256: string;
    byteLength: number;
  }>;
}
```

**Port caller must be trusted native host code.** The JS input schema above is *not* permission to pass plugin arguments directly to SQL or to accept a plugin's `verified:true`. `verifyReadablePlacement` must actually open/revalidate owned bytes and match cryptographic digest, using an owner-scoped credential/backend. A cached or pending placement is not sufficient.

## Adopted logical invariants for subsequent design review

- **Snapshot identity** differs from `ContentUnit` identity. One canonical unit may be preserved in multiple immutable revisions. A version-to-unit-to-object relation is needed; **do not overwrite** `content_units.storage_object_id` with an older revision or remap saved `ReadingSession.unitId`.
- Canonical source `unitIndex` can have gaps. Page manifest `ordinal` is contiguous 0-based *within a historical revision*. The active `ContentUnitOrder` governs which unit is displayed next.
- A committed preservation version must have immutable manifest hash, all expected page bindings, durable readable verified placements, and a pin/reference root if retention says pinned. Never insert `complete` based only on an in-memory candidate.
- `ownerScopeId` is obtained from an authenticated host context. It is not sourced from the website, plugin, HTTP request body or untrusted IPC field.
- Fresh-v2 databases have no legacy `comics/chapters/pages` tables. New relational contracts must be added to the single canonical v2 schema; use one migration version / rollback plan, not a sidecar DB authority.

## Atomic transaction acceptance gate

The trusted `commitPreservationBinding` implementation must:

1. Acquire a write lock; validate caller's authenticated owner, opt-in preservation grant, and exact snapshot/section binding.
2. Re-fetch the canonical work, section, active `ContentUnitOrder` and every unit; require `expectedOrderDigest` match and complete order, including same units, index evidence and current ordering. No outdated snapshot shall mutate the user's active order.
3. Re-fetch each `StorageObject` and `StoragePlacement`, validate scope, synced authority/mirror placement, bytes/hash/size proof and object identity. Pin/lease each referenced object against concurrent GC. The preflight proof must not be the sole authority if data can change before commit.
4. Insert version manifest and all unit/placement reference edges plus retention roots **atomically** with an idempotency receipt. Same `snapshotId + manifestHash` may replay; changed hash must conflict. A half-attached chapter is never visible as complete.
5. Publish visible state only after filesystem durability / journal reconciliation succeeds. Roll back or quarantine incomplete writes on any error.
6. Preserve original source linkage as evidence only. Do not write to or abandon `ReadingSession` as a side effect of saving a version.

The actual implementation will need a crash-safe two-plane journal across managed bytes and SQLite visibility; **SQLite transaction alone is not a filesystem transaction**. If the runtime cannot guarantee owner-scoped attachment and GC leases, reject `PRESERVATION_BINDING_NOT_SUPPORTED` rather than weakening the rule.

## Historical version lookup must outlive mutable Source Order

PR #7 now provides `readPreservedVersion({ownerScopeId,snapshotId})` in the **test-only SQLite binding proof**, followed by `readHistoricalPage` through trusted Store and Placement ports. This is deliberately distinct from `readSectionOrder` and `commitPreservationBinding`: it returns the **frozen saved unit order**, verifies owner and journal references in a single SQLite read transaction, cross-checks persisted page links against the immutable stored manifest, and rehashes the actual requested bytes before showing the historical page. An original source rewrite, HTTP 404, or new active page order must not invalidate an already saved version.

**Storage migration is not solved by this proof:** its fixture captures a specific `placementId` and is intentionally fail-closed when that placement disappears. Production Snapshot identity must pin **logical StorageObject/CAS identity**, not a permanently fixed physical backend/placement. A StorageResolver can select another owner-authorized, byte-verified authority/mirror after migration, using a separate durable move/replica journal. Do not rewrite an immutable manifest to chase backend paths or reuse the old placement's proof for a different backend. Test a local-to-NAS move and cloud restore explicitly before shipping.

The new historical read tests also check cross-owner denial, placement/hash drift, source-independent order, tampered reference edges, source deletion without unsafe remote fallback, and release of the consistent SQLite read transaction on both success and failure. These are fixture/contract tests, not an implemented Flutter reader.

## Reader selection

```text
UI intent (current version | saved version)
 -> ReaderOpenTargetResolver (canonical unitId + active unit order)
 -> PreserveVersionResolver (explicit snapshotId or latest complete pinned)
 -> PlacementResolver (verified owner-scoped bytes)
 -> Image loader
 -> ReadingSession(unitId), only when actual navigation occurs
```

For explicitly selected historical versions, fail closed if missing/corrupt; never silently fetch the current remote page as the purported old version. For default current reading, an absent preserved copy may use the runtime-authorized remote provider, but a corrupt owned copy should surface a distinct diagnostic rather than silently hiding integrity loss.

## Tests and fault injection required before shipping

- Source HTTP 404 or plugin removal, then restart app: all bytes of a committed snapshot available through canonical ReaderOpenTargetResolver.
- Concurrent page reorder between read and commit: transaction rejects; no content row, order, or position gets overwritten.
- Same title across sources / instance URL migration: no automatic source or content merge.
- Missing/evicted/corrupt / pending / cache-only placement, and cross-owner object: fail before or during commit, no partially visible snapshot.
- Power loss after managed blob promotion and before SQLite binding: journal reports uncommitted asset; no false complete snapshot.
- Recover a promoted verified object with a new trusted gesture, but do not grant automatic `ContentUnit` attachment authority.
- Replay exactly once under retry/race; new version with different bytes is a separate immutable snapshot, not destructive update.
- Concurrent GC, pin mutation or source deletion cannot remove live preserved bytes.
- Reader progress remains a canonical unit ID and is never reset when selecting a different snapshot revision.
- Full backup includes the transitive closure of the preservation version's bytes; restore uses matching identity and real verified placements.

## SQLite transaction prototype evidence (PR #7, not canonical)

The isolated [SQLite binding proof](../../tools/preservation-contract/src/sqlite-binding-proof.mjs) now implements the `readSectionOrder` and `commitPreservationBinding` **port shape** against Node `node:sqlite` using test-only fixture tables. It requires `BEGIN IMMEDIATE`, current active order digest CAS, same-owner content and committed storage journal, synced placement metadata, a synchronous caller-owned active-byte-lease attestation, all-page/position binding, and exact replay detection. It writes an immutable version, ordered page references, and a pinned root in a single SQLite transaction and rolls all rows back on injected errors.

This proves a **concrete SQL algorithm to review**, not adoption of a schema: the fixture uses only a subset of PR #6's current table columns and introduces `proof_*` tables that are not in canonical v2. The ownership table is deliberately synthetic because PR #6's current `contents` schema does not yet contain owner scope. The test's always-true lease callback is not a trusted native capability; production must supply an independently authenticated/locked lease and a DB/FS crash journal.

The added [Node SQLite tests](../../tools/preservation-contract/test/sqlite-binding-proof.test.mjs) include actual transaction rollback after one page insert, exact idempotent replay, changed-order CAS failure, journal mismatch, owner isolation, pending placement and partial active order failures, plus end-to-end **fake proof-store → publish gate → SQLite** composition. They are authored tests; verify live CI execution before claiming that all cases passed.

## PR dependency

- **PR #6**: accept/review the greenfield v2 host-owned storage and auth boundary (not yet merged to main).
- **PR #7**: RFC, local proof-store, pure contract validation, and `canonical-publish-gate.mjs` with fake trusted-port negative tests only.
- **Follow-up canonical change**: add table/port/use-case definitions to authoritative v2 docs and implement actual SQLite integration in `runtime/v2` with native host authorization. Only then wire Venera Flutter Reader and remote connectors.

No PR may label snapshots **canonically preserved** until that follow-up passes fault-injection and complete offline reader tests.
