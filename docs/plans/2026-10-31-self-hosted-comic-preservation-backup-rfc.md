# RFC: Self-hosted Comic Sources, Preservation Snapshots, and Portable Cloud Backups

> **Status: PROPOSED (RFC + isolated contract-test prototype), 2026-10-31.** This RFC does not claim an implemented provider, durable capture pipeline, cloud adapter, or restore flow. No production schema, plugin SDK, migrations, or runtime behavior is changed by this PR.
>
> **Authority:** existing `docs/design/v2/00_OVERVIEW.md` through `11_MILESTONES.md` remain canonical on `main`. This document is an adoption proposal, not a competing database schema or an implicit amendment to those contracts.
>
> **Coordination:** draft [PR #6](https://github.com/mythic3011/venera-next/pull/6) proposes `12_REMOTE_READING_ACCESS.md` (first-party private mounts and canonical asset resolution), `14_PLUGIN_RUNTIME_SECURITY.md` (typed capability broker), and `15_RUNTIME_CREDENTIAL_VAULT.md`. Those files are **not merged to main**. Reconcile this RFC with them before promoting anything to canonical files. The term *comic-preservation snapshot* here is unrelated to PR #6's short-lived legacy-import snapshot lease.

## 1. Decision requested

Build three independently usable layers:

1. **Self-hosted source connectors**: use Venera as the reader for a user-configured LANraragi, Komga, or Kavita instance, with stable source-instance identity, typed metadata/page adapters, and runtime-owned credentials. Remote archives remain owned by the server unless explicitly captured.
2. **Comic preservation**: capture an authorized, bounded, immutable *version of actual page bytes* plus the ordered-page and provenance manifest, so an already captured chapter remains readable after its origin changes, returns 404, or goes offline. Capture is opt-in and independently pinned against cache eviction.
3. **Portable app backup and cloud transport**: save app state (and optionally preserved media) into a versioned, integrity-checked, client-encrypted backup; support Local File, Google Drive, WebDAV, and S3-compatible destinations through small transport adapters. Restore must not require original source availability for media included in the backup.

**Do not equate** a normal online read, a cached thumbnail, a completed download, a preserved snapshot, a cloud replica, a library backup, or bidirectional multi-device sync. Each has different guarantees.

### Goals

- Read ZIP/CBZ/image content hosted on self-managed comic servers through canonical `Content → ContentSection → ContentUnit` and the existing reader.
- Maintain stable content and reading-position identity when an instance URL changes or a source becomes unavailable.
- Preserve older page revisions, allow deliberate version selection, and prove page bytes are available before declaring a snapshot complete.
- Restore metadata, position, collections/tags, provider references, settings, and optionally media on another device.
- Keep plugins, cloud SDKs, credentials, and arbitrary paths out of domain/reader authority.
- Make staging failures, network interruption, source deletion, and restore ambiguity explicit.

### Non-goals for the first release

- Scraping around DRM, paywalls, authentication failures, robots/access restrictions, or provider rate limits.
- Downloading every source/favorite by default, unlimited crawling, or a public redistribution service.
- Bidirectional position sync or cross-device concurrent write resolution (existing v2 is single-runtime last-write-wins).
- Secret/cookie export by default, third-party plugin access to LAN resources, or whole-database encryption claims.
- Building a replacement LANraragi/Komga/Kavita host as a prerequisite.
- Reusing old Venera JS source formats or the legacy runtime as canonical implementation authority.

## 2. Deployment and trust boundaries

~~~text
Venera UI (Flutter / web shell)
  -> application use cases + canonical reader/session
  -> AssetResolver / acquisition coordinator
      -> sandboxed public website Provider (public-only typed broker)
      -> trusted first-party SelfHostedConnector (user-granted exact origin)
           -> LANraragi | Komga | Kavita (NAS/Docker, HTTP API)
      -> verified owned StorageObject + readable StoragePlacement
  -> PreservationCapture (explicit background job + immutable manifest)
      -> local managed media / optional preservation replica
  -> BackupCoordinator (consistent state export, optional verified media)
      -> encrypt + authenticate backup envelope
      -> Local | Google Drive | WebDAV | S3 transport
~~~

A **first-party connector** can use the trusted runtime's narrowly scoped private-network transport. It must not hand that grant or raw HTTP client to an untrusted executable JS provider. This follows the separation proposed in PR #6 `12_REMOTE_READING_ACCESS.md` and `14_PLUGIN_RUNTIME_SECURITY.md`. If a later SDK supports externally installed private-network connectors, that requires a separately reviewed isolation/capability contract, not a broad SSRF exception.

**Authority table**

| Concern | Owner | Never owned by |
| --- | --- | --- |
| User intent, capture/restore approval | Trusted UI/use case | Website response/plugin |
| Server instance identity and account snapshot | Runtime domain + credential broker | URL text or plugin JS |
| Search/catalog/section/page mapping | Connector + canonical materializer | UI-created magic IDs |
| Content, units, order, reading position | Canonical domain/repos | Remote URLs or snapshots |
| Source HTTP authentication, private egress, redirects | Trusted network/auth broker | Plugin-supplied RequestInit |
| Page bytes, placement, GC protection | Storage ports | Metadata-only snapshot row |
| Preservation manifest, version and pin | Preservation service + transactional metadata | Normal cache policy |
| Backup selection, consistency, encryption, restore | Backup service | Google Drive/S3 adapter |
| Upload/download/list/delete backup objects | Destination transport | Domain repositories |

## 3. Self-hosted source connector contract

**Proposed logical model**, not approved DDL:

~~~ts
type SelfHostedKind = "lanraragi" | "komga" | "kavita";

interface SelfHostedInstance {
  id: string;                       // immutable instance UUID
  kind: SelfHostedKind;
  providerKey: string;              // immutable adapter identity
  displayName: string;              // mutable label only
  endpointRef: string;              // trusted config record, not identity
  credentialProfileRef?: string;    // opaque runtime-managed reference
  connectionRevision: number;
  status: "active" | "disconnected" | "reauth_required" | "disabled";
}
~~~

- The remote work key is scoped by **instance identity and source account scope**, not by hostname, display name, ZIP filename, or bare remote work ID. Use SourcePlatform/SourceLink conventions; reconcile with PR #6's proposed RemoteMount and account binding instead of establishing a parallel source ID allocator.
- Allow an explicit **reconnect/rebind wizard** after NAS IP, Tailscale hostname, credentials, or server migration. Rebinding an existing instance requires identity evidence and user approval; no same-title implicit merge. Reconnect must not silently change an unrelated account or borrow another server's cookies.
- Keep per-backend mapping adapters small: LANraragi is archive-centric; Komga and Kavita expose series/book or chapter structures. Normalize them into canonical sections and stable page evidence *before* reader resolution. Treat book/volume as containers if they have children; unit-bearing nodes must comply with existing section-kind rules.
- Search, detail, section listing, ordered page discovery and authenticated page retrieval are initial read-only capabilities. Provider writeback (progress, library mutations), pagination, thumbnails, offline downloads and server-side actions are separate capability gates.
- Do not hardcode assumed REST paths or stable remote page IDs as universal contracts; pin supported backend versions and verify actual API payloads/authorization/page-order behavior through fixture + live integration tests.
- The backend's original archives are external bytes, **not** verified local StoragePlacements by virtue of URL existence.

**Private-origin policy**: a trusted user grants an exact scheme/host/port/server instance (with optional approved DNS/IP constraints). At execution, independently enforce TLS policy, origin/account binding, private CIDR authorization, DNS resolution/pinning, every redirect hop, maximum response sizes, timeouts and concurrency. Deny cross-origin forwarding of credentials; deny loopback/link-local/metadata services unless a more specific audited first-party grant permits the intended endpoint. Treat Tailscale CGNAT and IPv6 ULA consistently. Revoked or revised grants invalidate queued privileged I/O. Untrusted JS providers retain public-only network access.

## 4. Preservation is not an ordinary download

### 4.1 Canonical relation

A preserved revision belongs to canonical content/sections, **not** directly to a mutable source URL. A snapshot is an immutable manifest over page evidence and owned verified bytes; the StorageObject/StoragePlacement model remains byte authority.

~~~ts
// PROPOSED type shape; names/columns require canonical adoption review.
interface PreservationSnapshot {
  id: string;
  ownerScopeId: string;
  contentId: string;
  sectionId: string;
  capturedFromSourceLinkId: string | null; // provenance only
  capturedAt: string;
  captureReason: "manual" | "favorite_opt_in" | "read_opt_in" | "update_opt_in";
  status: "capturing" | "partial" | "complete" | "failed" | "cancelled";
  expectedUnitCount: number | null;
  manifestSha256: string | null;    // only after immutable commit
  pinned: boolean;
}

interface PreservationManifestV1 {
  schemaVersion: 1;
  snapshotId: string;
  contentId: string;
  sectionId: string;
  sourceOrderEvidence: string;
  completenessEvidence: "stable_count" | "verified_end_marker" | "unverified";
  units: Array<{
    canonicalUnitId: string;         // reading position authority, if resolvable
    ordinal: number;                 // frozen within this snapshot
    storageObjectId: string;
    plaintextSha256: string;
    byteLength: number;
    mediaType: string;
  }>;
}
~~~

The `units` array freezes this revision's order. Never replace a snapshot's manifest/page bytes when a source reorders or modifies pages; capture a **new** snapshot. Snapshot IDs are not ContentUnit IDs. A source page ordinal, signed URL or filename does not prove identity; on weak evidence preserve an unresolved binding and require review rather than rewriting an existing saved `unitId`. A preservation manifest must not contain cookies, authorization headers, or time-limited download URLs.

### 4.2 Capture state machine and completion proof

~~~text
requested (consent + policy) -> queued -> capturing -> verifying -> committed complete
                                             |                 |
                                             |                 +-> immutable manifest
                                             +-> partial/failed/cancelled + durable report
~~~

- Resolve an authorized source/account snapshot, materialize canonical units/order through existing remote unit use cases, then acquire every selected page through bounded runtime fetch.
- Validate HTTP result, image magic/type/size, decoded limits and stable page-order evidence. Stream each page into private staging; hash and length-check; atomically promote verified owned bytes; only then commit referential metadata and snapshot manifest. Staging and DB visibility are **not automatically one cross-filesystem transaction**: use a recoverable journal, explicit crash checkpoints and orphan cleanup.
- A complete snapshot requires **evidence of the expected entire ordered page set**, all referenced units, verified byte availability, and committed readable placements. Unknown/unstable page counts may yield `partial` or `completeness_unknown` in a revised contract, but must never be mislabeled complete. A confirmed partial is a separate immutable preserved version; completing it later produces another version.
- A successful metadata request, HTTP 200, cache hit, StorageObject row, or download counter alone is not completion proof. Where the source cannot provide reliable completeness evidence, surface that limitation.
- Use SHA-256/content-addressed blob storage to deduplicate identical image bytes across versions. Hash equality is evidence for byte reuse, **not** a license to conflate works or pages. Keep manifest ordering and ownership separately.
- Respect `StoragePlacement`: at most one logical authority placement per StorageObject, other verified replicas are mirrors. A cloud-encrypted backup object is **not** interchangeable with a plaintext image placement.

### 4.3 Retention, garbage collection and source failure

- A **pinned** preservation snapshot is a durable retention root; its referenced StorageObjects/blobs cannot be evicted by normal cache cleanup, read-completion cleanup, DownloadQueue.autoDeleteAfterRead, source detach/uninstall, or provider deletion. Account for all pin references before any garbage collection, including concurrently running capture/restore.
- Storage budget pressure pauses new captures or requests an explicit user retention decision; it must not silently evict pinned versions. An optional unpinned retention policy may prune old revisions with dry-run impact display.
- Failed/partial captures never replace a previously complete snapshot. Source response 404, 401, 403, outage, changed bytes, archive rename, or plugin removal must not cascade-delete owned preserved media.
- Local deletion of an immutable snapshot must be a separate explicit action; a requested delete is followed by reference/liveness checks and background reclamation. Cloud copies have independent retention/versioning; remote backup deletion needs explicit approval and should not be a side effect of source loss.
- Reading-resolution priority (policy controlled): a user-selected verified snapshot; then latest verified complete snapshot for offline/fallback; then remote fetch if allowed/available; partial capture only with an explicit incomplete warning. Never silently show a changed page as if it were the selected historical version.
- Source URLs can be gone while a snapshot remains fully readable; a *metadata-only* backup cannot reproduce lost image bytes.

## 5. App backup versus media backup versus synchronization

### 5.1 Backup profiles

| Profile | Included | Excluded / guarantee |
| --- | --- | --- |
| Settings | app preferences, reader settings, installed-provider descriptors and non-secret connection configuration | no library state, media, cookies or tokens |
| Standard (default) | canonical metadata, source/instance references, collections/tags/favorites if implemented, history/active reading positions, settings, snapshot manifests **with missing-byte flags** | no image bytes; cannot promise offline recovery without existing storage |
| Full preservation | Standard plus explicitly selected, verified local archives/covers/preserved page blobs and their complete object dependency closure | quota/bandwidth sensitive; no secrets by default |

Unimplemented feature tables must not be claimed in exported payloads. The manifest must distinguish `included`, `not_included`, `unsupported_version`, and `unavailable` rather than silently dropping referenced objects.

**Backup is a point-in-time export**. Cloud replication is another durable copy of that export or of selected preservation objects. **Sync** would reconcile concurrent client mutations and requires its own conflict/version policy; do not infer sync from backups or from a shared cloud folder.

### 5.2 Proposed backup boundary and destination adapters

~~~ts
type DestinationKind = "local" | "google_drive" | "webdav" | "s3";
type BackupMode = "settings" | "standard" | "full";

interface BackupPlan {
  mode: BackupMode;
  destinationId: string;
  mediaSelection: "none" | "pinned" | "selected";
  encrypt: true;                     // cloud transport always uses portable encryption
  policyRevision: number;
}

interface BackupTransport {
  list(): Promise<readonly BackupObjectInfo[]>;
  uploadStaged(
    objectId: string,
    chunks: AsyncIterable<Uint8Array>,
    expectedCiphertextSha256: string
  ): Promise<UploadReceipt>;
  open(objectId: string): AsyncIterable<Uint8Array>;
  delete(objectId: string): Promise<void>; // explicit retention operation only
}
~~~

Transport interfaces carry **opaque encrypted bytes**, no SQLite handles, no unencrypted canonical domain objects, no Vault secret values and no unrestricted file access. Destination config is schema-versioned and its OAuth/access-key material is stored in runtime-owned secure storage by secret reference.

- **Google Drive**: user-selected, visible app-created folder under My Drive using OAuth Authorization Code + PKCE when applicable, narrow `drive.file` scope, and resumable uploads. The hidden `appDataFolder` may be offered as an alternative but **must not** be the sole disaster-recovery copy. OAuth reauthorization is expected after reinstall; backed-up app data does not require the original token.
- **WebDAV**: scoped collection path and credentials with an explicit trusted origin grant; conditional writes/temporary keys where available.
- **S3-compatible** (AWS S3, MinIO, R2 where supported): bucket/prefix scoping, multipart upload when beneficial, verified object completion, optional bucket versioning/object lock configured separately. Never claim provider-neutral object-lock guarantees.
- **Local**: atomic local export to a user-chosen path; verify the resulting backup after writing, and make it portable.
- Normalize retry/idempotency and resumable upload receipts; cancellation must leave no committed backup manifest referring to missing parts.

### 5.3 Consistent, encrypted format

The canonical data store must be backed up through a **consistent SQLite snapshot or approved logical export**, never by casually copying an active DB file without its WAL state. A cloud backup contains:

~~~text
venera-backup/
  envelope.json                 # minimal, authenticated format/KDF metadata
  encrypted-manifest            # version, provenance, inclusion inventory
  encrypted-app-state           # canonical logical records or consistent snapshot
  encrypted-objects/*           # optional deduplicated media chunks
  commit-receipt                # published only after all referenced blobs verify
~~~

This is a logical layout; actual physical packaging may be streamed/chunked rather than one giant ZIP. Full media backup should support content-addressed reuse/incremental upload **only after** a complete restore-able dependency inventory is validated. Do not allow incremental chains that can be broken by pruning an older base snapshot.

Encryption/key handling:
- Use an audited authenticated-encryption implementation (e.g. AES-GCM or XChaCha20-Poly1305) with correct nonce uniqueness and per-chunk authentication/AAD. If passphrase-derived, use a documented memory-hard Argon2id KDF with versioned parameters; offer a randomly generated recovery key as an alternative.
- Authenticate envelope metadata and media inventory, not just ciphertext contents. Hash plaintext locally for dedupe/integrity; avoid exposing meaningful filenames/titles/page URLs and raw plaintext hashes as unnecessary cloud-visible metadata.
- **No cookies, passwords, API keys, OAuth refresh tokens or host Vault contents by default.** Optional portable credential export would be a separate user-approved security design, not an accidental "Full" mode option.
- A cloud provider outage or successful HTTP response does not prove a usable backup. Verify upload receipts/inventory and periodically exercise **decrypt + dry-run restore**. Retention can keep e.g. 7 daily / 4 weekly / 6 monthly *unpinned* backup generations; never delete a backup's referenced chunks while still live.

## 6. Restore contract: availability and identity before mutation

~~~text
select backup -> download -> authenticate/decrypt -> schema & integrity checks
  -> dry-run identity/instance/media reconciliation -> user decision
  -> staged media + transactional canonical apply -> verify reader targets
  -> commit receipt, unresolved references kept as explicit review state
~~~

1. Reject unknown/incompatible backup schema or broken signatures/tags/hashes/size budgets **before** changing canonical state. Support documented version migrations, with a no-mutation dry run.
2. Match a work by the existing identity ladder: SourceLink (instance/account scoped) -> strong content/fingerprint evidence -> title **as a proposal only**. Default ambiguous matches to `keep_both`, never automatic same-title merge.
3. If the saved self-hosted instance URL is no longer accessible, offer explicit rebind and account reauth. Rebind does **not** mutate content identity just because a hostname changed.
4. Restore reading positions only when the referenced canonical `unitId` is verified/reconstructed against the intended content, section and page binding. Never invent placeholder IDs or rewrite page index evidence into a fake active ReadingSession. Preserve unresolved position evidence for manual resolution.
5. Apply `merge` without deleting unrelated local data; `replace` requires separate confirmation and rollback/recovery plan. Restore must not overwrite a newer saved position silently; conflict outcomes are visible even without multi-device sync support.
6. If full preserved bytes are present, the reader must work with the source disconnected. For Standard/Settings-only backup, report missing media and allow reconnection; do not promise offline recovery.
7. The restore operation must be idempotent under replay and crash-safe across blob staging/DB visibility. A partially applied restore must be detected and resumed/rolled back, not counted as success.

## 7. Security and privacy gates

| Risk | Required gate |
| --- | --- |
| Malicious website/plugin asks for NAS/localhost or cloud credentials | No shared private-network grant; typed broker authorization per request, owner/account scoping, deny-by-default |
| DNS rebinding / redirects / Tailscale/private IP ambiguity | Exact origin/IP policy, resolve-pin-connect, redirect revalidation, no cross-origin auth forwarding |
| ZIP bomb, traversal, corrupt CBZ, hostile image | archive/decoded byte budgets, extension-independent magic detection, bounded parsing, no traversal or unsafe extractor paths |
| Credential/token exposure in backups, plugin logs or manifests | Vault reference only; redact URLs and TIER-0 content from diagnostics; encrypt backup, exclude credentials |
| Source deletion causes permanent local data loss | Preservation refcount/pin roots, source unlink never cascade-deletes owned snapshot |
| Mixed version or stale page binding corrupts saved position | Immutable per-revision order/evidence, preserve Unit IDs, explicit reconcile conflict |
| Crash during capture, upload, GC or restore | private staging, durable journal/receipt, SQLite visibility transaction, fault injection, safe cleanup |
| Attacker modifies cloud backup/object list | authenticated encryption, manifest dependencies, verified restore; optional independently stored rollback/version evidence for stronger threat models |
| Device theft or leaked cloud token | portable backup encryption separate from cloud OAuth; revocable credentials; no plaintext cloud copy |

Remote content preservation must respect applicable usage rights and server permissions. Do not implement CAPTCHA/DRM bypasses or unbounded fetching. Explicit per-source policies include rate/concurrency limits, metered/mobile data controls, storage budgets and user-controlled capture scope.

## 8. Product behavior and proposed defaults

- Manual `Save Snapshot` is enabled once a source and storage backend support verified acquisition. Auto-capture is **off by default**; optional modes: favorites, on-read chapter, new/changed chapter. Each has clear opt-in, scope and network/storage costs.
- A `Preserved` indicator only appears after a verified local complete snapshot; `Partial` and `Backup metadata only` are distinct states.
- Allow `Open Current Source`, `Open Saved Version`, `Compare/Select Versions`, `Pin/Unpin` and a clear delete impact preview.
- In Source settings, configure/add LANraragi/Komga/Kavita via explicit server connection wizard; separate `Connection unavailable` from `Credentials required` from `Content deleted`.
- In Backup settings, configure destination, backup profile, schedule, encryption recovery method, retention policy, test-restore and last verified receipt. A scheduled task is not proof of successful backup.
- Export of installed plugin references is data only; installed executable package artifacts require normal repository verification on restore, never blind execution of embedded JS.

## 9. Delivery slices and testable exit gates

| Slice | Milestone alignment | Exit proof |
| --- | --- | --- |
| A: read-only LANraragi connector | M3 remote source/security gates | server -> search/detail/sections/pages through canonical reader; stable position, no private grant leak to JS |
| B: Komga and Kavita connectors | M3 after A | differing Series/Book/Archive shapes normalize without losing section order/identity |
| C: local preservation | M3 download/materialization follow-up; no M1 scope expansion | complete/partial contracts, verified immutable versions, source-404 offline read, pinned-GC protection |
| D: portable local Standard backup/restore | M5 backup; may be prototyped earlier without moving M1 gate | metadata restore, missing-source and unresolved-position dry-run, no credential export |
| E: Full media + cloud transport | M5 after D/C dependencies | encrypted Google Drive/WebDAV/S3 backup, offline cross-device restore, resume interrupted upload |
| F: hosted / multi-device extensions | M4+ and separate sync design | owner-scoped permissions, explicit concurrent position conflict semantics; not inferred from backup |

**Acceptance and negative tests (must be automated when implementation exists):**

1. Capture a full chapter; simulate HTTP 404, DNS failure and plugin removal; every captured page remains readable offline with identical SHA-256.
2. Origin changes one image and order; a new version is distinct, old manifest immutable, saved `unitId` not silently rebound to different bytes.
3. Capture interrupted after staged page, before DB commit, and after promotion; recovery never publishes a false complete snapshot or leaks permanent orphan bytes.
4. Partial capture and unknown page count never acquire `complete` status without full evidence; existing complete revision remains selectable.
5. Cache eviction, read-complete deletion, source detach, local quota pressure and concurrent GC cannot evict pinned preservation bytes.
6. Two works with equal titles/cover but different source IDs remain distinct; a server migration requires explicit verified rebind.
7. JS provider attempts a LAN request, redirect to loopback and auth header forwarding; all fail without borrowing first-party grant.
8. Backup Standard restores progress/collections but explicitly reports missing media; Full restores chapter offline after source removal.
9. Encrypted cloud backup fails closed on wrong recovery key, truncated ciphertext, missing media chunk and tampered manifest; no mutation.
10. Power loss/retry mid-backup upload and mid-restore produces one valid receipt or recoverable uncommitted staging, never half-valid success.
11. Restore into a populated library preserves independent user state; ambiguous merge chooses keep-both; unreadable/stale positions remain unresolved, not fabricated.
12. Restored plugin references cannot execute code until regular signature/artifact verification and permission approval have completed.

## 10. Adoption checklist / open decisions

This RFC is deliberately **not** new canonical authority. Adoption requires a reviewed cross-file change:

- `01_ENTITIES.md` / `02_DATABASE_SCHEMA.md`: owner-scoped instance/credential references; preservation snapshot/version/page records and pin/reference lifetimes; backup job/inventory/receipt records with FK and journal invariants.
- `03_USE_CASES.md`: capture, list versions, pin/unpin, select version, delete with impact, restore dry-run/apply and reader fallback rules; keep existing `ReadingSession.unitId` authority.
- `04_PACKAGES_AND_PIECES.md`: first-party connector, PreservationCapture, Storage/GC, BackupCoordinator and BackupTransport ports with explicit dependency direction.
- `05_PLUGIN_SYSTEM.md` / `06_SECURITY_AUTH_RECOMMENDATION.md`: public-only JS provider vs first-party private connector grant, credentials and transport permissions (coordinate with draft PR #6).
- `07_FEATURES.md`: distinguish verified preservation from DownloadQueue/cache and existing UC-BACKUP-001/002 metadata-only scope; separately gate future hosted sync.
- `08_SOURCE_PACKAGE_LIFECYCLE.md` / `09_OBSERVABILITY.md`: package restore verification and privacy-safe job/receipt diagnostics as necessary.
- `10_MVP_SCOPE.md` / `11_MILESTONES.md` / `SUMMARY.md`: keep M1 standalone import/read/resume scope intact; stage M3 acquisition and M5 backup; add explicit acceptance gates.

**Decisions to review before code:**
1. First-party connector implementation: built-in typed adapters vs a new verified `remote_mount` type; either way no direct LAN privilege for third-party JS.
2. Storage and version lifecycle schema: immutable manifest commit representation, incomplete captures, pin references, ownership and source-detach FKs.
3. Preservation default: manual-only vs explicit per-source auto-capture opt-in; quota, retention and replication choices.
4. Backup packaging: logical portable export vs SQLite backup; chunking and authenticated format/version migration plan; recovery-key UX.
5. Restore merge safety when original server instance, source package or page bindings are gone.
6. How draft PR #6's proposed RemoteMount, Broker, Vault, one-way legacy import and platform-specific filesystem grants are adopted without duplicate authority.

### Isolated reference harness in this PR

A standalone Node.js module in [`tools/preservation-contract/`](../../tools/preservation-contract/README.md) exercises a **small, pure subset** of the design, without importing or modifying `runtime/core`, the pending `runtime/v2`, or client data:

- `buildCaptureCandidate` hashes caller-provided image bytes; rejects unsupported MIME/magic, duplicate unit/ordinal IDs, different bytes reusing the same StorageObject ID, and unauthorised raw URL/secret fields. It preserves a deterministic, frozen, ordered manifest.
- `complete_candidate` requires trusted count evidence and every expected page; unknown counts or missing pages produce `partial_candidate`. Neither state **commits** image bytes or proves that a remote provider honestly reported all pages.
- `planSnapshotPrune` produces a **dry-run only** object list; pinned/staging snapshots, shared blobs, and active acquisition/restore leases are protected. It rejects missing references, unknown prune IDs and duplicate identifiers. Orphans are not reclaimed by this operation.
- Unit and negative tests run using Node.js `node --test tools/preservation-contract/test/*.test.mjs`; the separate `.github/workflows/preservation-contract.yml` is intended to run on matching PR changes.

The harness intentionally has **no** runtime integration, true image decoding, trusted storage attestations, crash journal, actual garbage collection, encryption, backup transport, restored app state, credential handling, or LANraragi/Komga/Kavita API calls. Production GC must recheck liveness under a lock immediately before deletion. Deployment of first-party connectors still depends on the unmerged security and identity design from PR #6.

**PR scope:** RFC plus isolated reference harness and focused tests; not a user-facing implementation. Unit tests do not demonstrate safe durable capture, provider authentication, encryption, cloud backup, restore, or source-deletion E2E behavior.
