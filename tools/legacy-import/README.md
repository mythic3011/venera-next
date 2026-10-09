# Old Venera distributed-data inspector (L0)

**Status: early L0 inspector plus trusted local-console evidence approval.** No comic/media/settings/reading-position import, account login, plugin execution or old-file mutation. The opt-in host console Wizard can persist **only** an `evidence_only` Dataset/Approved Batch to an already-existing fresh-v2 canonical database. Uses only five allowed old-Venera roles:

- `local.db`
- `history.db`
- `local_favorite.db`
- `appdata.json`
- `implicitData.json`

The old Unified Store `venera.db` is **never** an accepted import role (including when renamed, using schema detection). The *new* v2 `data/venera.db` must never be used as input.

## Run

Requires **Node >=22.16** with the experimental built-in `node:sqlite` module. The **recommended reference isolation path** is Docker on Linux or macOS with Docker Desktop. First pull the specified trusted Node image, then run the fail-closed launcher:

```sh
docker pull node:22.16.0-bookworm-slim
node tools/legacy-import/preview-isolated.mjs --dir "/path/to/old-venera-data"
node --test tools/legacy-import/test/*.test.mjs
```

`preview-isolated.mjs` starts the inspector inside a separate Docker container with `--network=none`, read-only root + mounts, non-root host UID/GID, dropped Linux capabilities, no-new-privileges, private bounded tmpfs, CPU/memory/PID budgets and a host-side runtime deadline/output cap. It **does not** fall back to direct JS when Docker is absent or fails. The source directory is mounted **read-only as a whole**; if it contains unrelated sensitive files, a compromised parser may still read them within the container (although outbound network is blocked). Use a **dedicated directory containing only the five selected distributed files and SQLite WAL/SHM sidecars**, not a shared home directory. The image tag is currently version-selected, **not digest-pinned**; pin/verify an image digest and audit the Docker daemon/runtime before shipping.

The original `preview.mjs` runs **without OS isolation** and is retained for controlled developer fixture/debug work only. Node subprocesses/Workers do not themselves provide this isolation. Windows/native macOS sandbox alternatives need their own verified adapters rather than an unsafe transparent fallback. No plugin or public HTTP API can trigger this trusted host-only tool.

The CLI reads only the five exact basenames in the explicit directory; unknown files are ignored, not discovered or treated as a fallback. The Docker path validates the subprocess response again through `sanitize-result.mjs`: only a fixed, bounded set of counters/status codes can cross to host UI; injected result fields, private titles and arbitrary error strings fail closed. Output is **aggregate schema/count/deferred statistics** and typed error codes only. It does not expose titles, history items, usernames, URLs, raw JSON, filesystem locations or content hashes. It returns a no-input status when all five are missing.

- For SQLite input, L0 opens source via `DatabaseSync({readOnly:true})`, runs `backup()` to an app-private temporary snapshot and inspects the snapshot with `query_only` and `trusted_schema=OFF`. This includes committed WAL changes visible to SQLite; journal sidecars may be used only internally by SQLite, not as sixth/seventh metadata types. If SQLite cannot obtain a consistent backup, it rejects that role; it does not fall back to copying raw DB bytes.
- Input filenames are enforced with regular-file and symlink checks; renamed Unified Store is denied by schema signature. Signature checks are a conservative **known-variant allowlist**, not proof of harmlessness for arbitrarily crafted SQLite databases.
- `local.db` reports metadata candidates, but **no comic is called readable yet**; media-root authorization and page identity validation belong to L1.
- `history.db` positions are **review required**, never promoted to canonical ReadingSession in L0. Its `image_favorites` are counted as a distinct deferred category.
- `local_favorite.db` folder content is counted and deferred until M2; quoted dynamic SQLite table names are validated and quoted as identifiers, never accepted as SQL fragments.
- `appdata.json` has a tiny explicit typed settings-candidate whitelist, still **deferred** until an approved v2 mapping exists; unknown fields are skipped. `implicitData.json` has zero auto-importable keys at L0; all contents are skipped. This prevents session/token/source-code copying.
- A `preview_only` status is **not** approval, import, verification of media, or permission to modify anything. `canCommit` is always false. No durable Batch, Dataset, RecordMapping, Journal or Receipt exists in this L0 tool.


## Five-file Record Attestation (L0)

The isolated `record-provenance.mjs` now produces typed, versioned per-record commitments from the **same inspected snapshots** for `local.db.comics`, `history.db.history`, `history.db.image_favorites`, dynamic per-folder `local_favorite.db` memberships, and **allowlisted non-sensitive** `appdata.json.settings` keys. `implicitData.json` is deliberately represented by an **empty proof**: no key, token, cookie, or password can become a mappable record.

Evidence goes into the host-private `.record-evidence.json`, **not** stdout. `docker-sandbox.mjs` checks per-role record counts against the inspected Preview; the lease checks exact file SHA-256, identity type and duplicate keys. `mapping-repository.mjs` denies any mutation whose exact key and record digest did not occur in the approved lease. Altering an original after Preview cannot modify pinned records; changing a record requires a newly reviewed/approved snapshot.

**Attestation ≠ import.** Record Mapping is evidence only. The L0 trusted console can create an approved *evidence-only Batch*, but cannot write Content, Storage, Reader Position, favorites, account data or settings. Future application operations require new feature-specific user approvals and canonical use cases.

## Trusted local-console Wizard (developer reference, not the Desktop GUI)

The new host-only `wizard-console.mjs` coordinates the same OS-isolated Snapshot, verified Lease and approved Batch. It requires a **pre-existing fresh-v2 canonical SQLite DB** containing all six legacy-import tables. It never initializes a database, ports the discarded runtime, mutates old input files, or imports comic content.

```sh
# Node >=22.16; Docker image already pulled and independently verified.
node tools/legacy-import/wizard-console.mjs \
  --source "/path/to/old-venera-distributed-files" \
  --canonical-db "/path/to/existing-fresh-v2.db" \
  --dataset-label "My old Venera installation"
```

For a previously associated dataset, use `--dataset-id UUID` instead of `--dataset-label`. The CLI demands **real interactive stdin/stdout TTY**, refuses headless flags/implicit YES, requires a new randomized phrase bound to the snapshot Plan Digest, and consumes every verified gesture **once**. Wrong phrase, timeout, cancellation or an expired/revoked Lease cannot create an Approved Batch. Any failed approval also revokes the in-memory lease.

For this developer-only terminal boundary, the local principal is derived from the current Unix UID (`local-console-uid:<uid>`); this is **not a production authenticated Venera identity**, OS-presence attestation or secure remote login mechanism. It must not be wired to an ordinary renderer, plugin, source JS or network endpoint. The final Desktop UI needs a dedicated native trusted dialog + authenticated host principal, not a renderer-originated `confirmed=true`.

**Approval grants only `evidence_only` scope.** The Wizard stores Dataset/Batch metadata and **zero canonical Content, Section, Unit, StorageObject, ReadingSession, UserCollection or user-settings records**. The SQLite DDL now enforces this scope; any later importer needs a separately designed, reviewed and consented content-import authority. The memory lease is short-lived and auto-evicts buffered source data; the application cannot silently resume from a stale approved Batch after restart.

## Known L0 boundaries

- `docker-sandbox.mjs` provides a **tested Linux-container boundary** on GitHub Actions. It is a reference adapter, not a universal mobile/desktop sandbox or a proof against every Docker/kernel vulnerability. A compromised Docker daemon is trusted-host compromise. Per-platform production isolation, runtime Docker image digest pinning, tighter per-file mounts and process/IPC audits remain open. CI now verifies the known official manifest digest and can fall back to its ECR mirror when Docker Hub throttles.
- Resource checks are bounded by per-file max bytes, per-table row count, JSON depth and node count, but `quick_check`/backup can still consume CPU on adversarial databases. OS process limits/timeout are required before shipping a general import wizard.
- `record-identity.mjs` implements **pure, deterministic six-part dataset-scoped record keys**. `mapping-repository.mjs` now implements a **trusted-host-only** dataset/mapping persistence adapter using the canonical `02_DATABASE_SCHEMA.md` DDL; CI executes the authoritative SQL against SQLite and tests owner-scope, conflict, dedupe and changed-pending semantics. It neither creates another sidecar database nor initializes schema or allocates Content IDs. `approval-gate.mjs` now implements the host-side, callback-verified **approved batch** transition. New Dataset creation is atomic with the approved batch; `reserveAfterApprovedPlan` requires the approved batch ID, matching digest, same dataset/owner and included file role, and refuses cancelled batches. **Implemented for controlled L0:** `export-snapshots.mjs` runs in the network-disabled Docker sandbox, exports and validates the exact same old-data snapshots into a host-private, short-lived staging directory, then `previewAndIssueSnapshotLease()` copies those bytes into `TrustedSnapshotLeaseRegistry` (owner/dataset, SHA-256 role manifest, TTL, revocation). Staging bytes are zeroed in memory and the temporary directory is removed; `approval-gate.mjs` binds approval to `leaseRef`, and `mapping-repository.mjs` re-verifies its live manifest on every mapping mutation. **Now present:** a host-only local interactive TTY confirmation verifier and five-role record provenance. **Still absent:** native Desktop Import Wizard UI, authenticated application principal, OS dialog confirmation, crash-recoverable snapshot store, asset/media grants, journal/receipt writing, ContentUnit reconciliation and Import Apply. The memory lease is lost on process restart; no silent resume against mutable original files. Test-only callbacks returning true are **not production authorization**. The L0 preview CLI remains read-only and cannot trigger approval.
- Login credentials, cookies, website account profiles, legacy source JS, legacy `syncdata.json` and Unified Store are outside this contract.

Canonical design: [17_LEGACY_DISTRIBUTED_IMPORT.md](../../docs/design/v2/17_LEGACY_DISTRIBUTED_IMPORT.md) and [03_USE_CASES.md](../../docs/design/v2/03_USE_CASES.md) (UC-LGI-001–004).
