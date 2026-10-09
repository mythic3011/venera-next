# Venera Implementation Milestones

> Companion to `10_MVP_SCOPE.md`. Maps the P0–P7 build ladder (06 § Implementation Priority)
> into shippable product milestones, and assigns every open review finding
> (`REVIEW_FINDINGS_2026-07-02.md`) to the milestone whose code it gates.
>
> Principle: **the P-ladder orders layers; milestones order value.** Each milestone is a
> vertical slice that ships something a user can feel, built only on layers the ladder
> has already made available. No milestone starts code whose design contract is still open.

---

> **Greenfield reset (2026-10-09):** retire the existing legacy runtime code. Start M0 from canonical v2 documents and fresh interfaces/storage schemas, not by porting old `Comic/Chapter/Page` implementations. M1 local-only and M3 online remain milestones; there is no in-place old-runtime or old-DB migration workstream. The separate one-time legacy import accepts **only** `local.db`, `history.db`, `local_favorite.db`, `appdata.json`, and `implicitData.json` from old Venera. Unified Store `venera.db` is excluded (see proposed `17_LEGACY_DISTRIBUTED_IMPORT.md`). See `16_ACCOUNT_PASSKEY_ADOPTION_CONTRACT.md` (proposal) for account-scoped identity and downloaded-content authority decisions.

## Milestone Map

```
M0  Foundations & doc-fix batch      (P0)             — no user-visible product
M1  MVP: import → read → resume      (P1)             — first shippable build      ★ MVP
M2  Organize: collections/tags/search(P1/P6 subset)   — library becomes livable
M3  Go online: plugins & sources     (P4 + N8)        — the "Venera moment"
M4  Hosted mode: auth & API          (P2 + P3)        — self-host release
M5  Daily-driver features            (P6 subset)      — notifications/stats/backup/filters
M6  Recommendation & discovery       (P5)             — graph, fingerprints, vectors
M7  Observability & hardening        (P7)             — audit chain, OTel, ops polish
```

Dependency shape: M0 → M1 → M2 → M3 → {M4, M5} → M6 → M7.
M4 and M5 are parallel-safe after M3 (different subsystems, no shared open contracts).
M7 items may be pulled earlier opportunistically; they are batched last only because none block correctness.

---

> **L0 implementation evidence (2026-10-10; partial, not a product release):** `tools/legacy-import/l0.mjs` performs no-commit five-file preview; `docker-sandbox.mjs` + `preview-isolated.mjs` add a tested Docker reference boundary (network disabled, RO mounts/root, resource limits and no unsafe fallback); `sanitize-result.mjs` validates/declassifies the subprocess output in the host; `record-identity.mjs` provides pure dataset-scoped six-part keys without allocating canonical IDs. `.github/workflows/legacy-import-l0.yml` runs Node 22.16 fixture tests and live Docker smoke. **Now in code:** a host-only mapping adapter persists Dataset/RecordMapping directly to canonical v2 tables once the caller has completed trusted approval; standalone tests execute schema SQL from 02 and verify reimport/ownership. **Implemented as a testable host-side contract:** `approval-gate.mjs` checks injected trusted user-gesture and exact source-snapshot revalidation callbacks before atomically creating an approved batch (and, for new datasets, the dataset itself). `mapping-repository.mjs` now denies mapping writes without a matching non-cancelled batch, owner, plan digest and file role. **L0 bridge implemented in Draft PR #6:** Docker worker exports and validates the same five-role SQLite/JSON snapshots, temporary host-private staging is handed to an expiring memory-only SnapshotLeaseRegistry, and Approval/Mapping now enforce owner/dataset/file manifest/lease validity. GitHub Actions includes a live Docker Snapshot → Lease test (including modifying the original file after Preview). **Not yet implemented:** production UI gesture verifier, persistent OS-protected crash-recoverable lease, record-level source evidence attestation, end-user wizard, media grants, asset journal/receipt writer, canonical Content import and multi-platform sandbox signoff. Approval currently only gates mapping reservations, not whole-library import. No user source files or v2 database are written.

> **Five-file evidence gate (2026-10-10):** L0 now attests local comic rows, history and image favorites, dynamic favorite-folder membership and reviewed appdata settings, all against immutable snapshots. `implicitData.json` intentionally has an **empty** proof: no implicit data is eligible to map. Evidence may be reserved under live approval, but no category is automatically imported into canonical Content/ReaderSession/Collection/Settings. Docker five-role E2E and negative tests are part of the CI gate. This is **not** the L1/L2 importer or Trusted Wizard UI.

### Separate one-time legacy-data import milestones (not a runtime migration)

> Proposed contract: [17_LEGACY_DISTRIBUTED_IMPORT.md](17_LEGACY_DISTRIBUTED_IMPORT.md). Input files **only**: `local.db`, `history.db`, `local_favorite.db`, `appdata.json` and `implicitData.json`. Old Unified Store `venera.db` is excluded. Journal sidecars (`-wal` / `-shm`) are SQLite snapshot mechanics, never extra import types. The importer does not depend on the old runtime.

| Phase | Earliest dependency | Exit gate |
|---|---|---|
| **L0 — Safe snapshot / dry run** | After **M0** | Five-file allowlist; read-only WAL-consistent SQLite snapshot, strict schema/JSON parsing; stable dataset-scoped LegacyRecordKey; typed preview, quotas and malicious-input tests |
| **L1 — Local content + resume** | After **M1** | `local.db` mapped to canonical Content/Section/Unit; verified media and complete active unit orders; `history.db` matched to Unit only when old chapter/page/index semantics are proven; durable filesystem+DB recovery |
| **L2 — Collections, tags, settings** | After **M2** | `local_favorite.db` folder order/memberships; allowlisted `appdata.json` and `implicitData.json`; import tag mapping only after M2 taxonomy contracts. Image favorites remain a **distinct deferred category**, not UserCollectionItem |
| **L3 — Optional source-only review** | After **M3** | User-reviewed remote history/favorite provenance under SourceInstance/AccountProfile; no automatic plugin execution, login, credential reuse or network fetch |

**Cross-phase correctness and acceptance:**

- Separate **batch snapshot fingerprint** from **dataset identity** and **per-record stable mapping**. A retry or changed settings JSON cannot duplicate mapped comics, collections or history; different installations with identical old IDs cannot collide.
- SQLite and filesystem are not one atomic resource. Use staged bytes, hash verification, durable intent, same-volume atomic promotion or validated copy/rename, canonical DB visibility commit, receipt recovery and orphan garbage collection. Simulated crashes at each boundary cannot expose half-imported active unit orders or broken StoragePlacements.
- Old `ep` / `page` / `readEpisode` / `chapter_group` do not identify a v2 Unit. Verify matching identity and index-base semantics; if ambiguous, preserve typed staging evidence and do not create/update ReadingSession. Existing v2 progress never rewinds silently.
- Import only from explicit trusted UI gesture. Source files and selected media roots remain unchanged. Credentials, source executable JS and the Unified Store are excluded.
- A user-facing **"import all five"** promise is complete only if all requested categories were verified. Otherwise return **partial/deferred** with a durable, auditable (redacted) receipt and separate review lifecycle.
- Tests must cover malicious SQL folder names, active WAL, symlink/media escape, missing folders, wrong-source `venera.db`, changed-only JSON, duplicate attempts and account/source unresolved evidence.

## M0 — Foundations & Doc-Fix Batch

**Goal**: A repo where every later milestone writes code against settled contracts. Nothing user-visible ships; the exit artifact is green CI on an empty-but-real architecture.

**Idea**: Cheap doc fixes get exponentially more expensive once code cites them. Batch every pure-documentation finding here, before the first line of dependent code, so no later milestone inherits a known-broken contract. This is also where the "registry completeness" CI checks land (Recurring Theme 4) — mechanical guards are cheapest when the registries are still small.

### Deliverables

1. Monorepo scaffolding, TypeScript config, test runner, lint rules — including the **boundary lint** (no framework imports in domain/application/ports; MVP acceptance #9) from day one.
2. P0 leaf packages: `@venera/events`, `@venera/permissions`, `@venera/tags`, `@venera/i18n`, `@venera/content-profiles`, `@venera/schema`.
3. Migration baseline for the MVP schema subset (10 §3.2) — consolidating `import_jobs` DDL into 02 as it lands (prior finding #4, first installment).
4. Repository ports (interfaces only) + adapter-sqlite skeleton + adapter-memory for tests.
5. CI checks: event-name registry vs docs (N18 guard), ports vs entity blocks (N10 guard), boundary lint.

### Design gates closed in M0 (doc edits, do first)

| Finding | Edit |
|---|---|
| N1 | `content.updated` becomes the single event name (04) |
| N2 | `anonymous_session_id` rename in 07 + 06; entity/DDL reconciled |
| N3 | One manifest authority in 05; `archiveSha256` stays in signed index only |
| N5 | Rating scale unified + CHECK + fail-closed rule (07/01) |
| N6 | 07's `content_fts` block → cross-reference |
| N12 | ImportJob `pending → cancelled` + startedAt reword (05) |
| N14 | Importer examples corrected; `querySqlite` added to ImporterUtils (05) |
| N15 | Intent comment on `recommendation_feedback` FKs (02) |
| N16 | Annotation offset CHECKs (02) |
| N18 | Six event stream modules added to 04's catalog; 09 families completed |

2026-07-07 correction batch also closed the remaining design-contract findings
(N4, N7, N8, N9, N10, N11, N13, N17, N19, N20). The milestone sections below
now describe when those contracts are implemented, migrated, and tested.

### Exit criteria

- `pnpm test` green with adapter-memory; migration baseline applies to a fresh SQLite file; boundary lint fails a deliberately-wrong import in CI.

---

## M1 — MVP: Import → Read → Resume ★

**Goal**: The `10_MVP_SCOPE.md` build, exactly as scoped there. First binary a real user can run.

**Idea**: Prove the four load-bearing contracts (position lifecycle, order completeness, storage split, import repair) before building anything on top of them. Milestone-level details, acceptance criteria, and cut lines all live in 10 — this entry exists so the sequence reads in one place.

### Deliverables (summary — authority is 10_MVP_SCOPE.md)

- Content/reader/import use cases wired end-to-end through adapter-sqlite + adapter-electron.
- Bundled `importer-archive` + `importer-directory` running through the real `defineImporter` protocol (shared isolation, no install pipeline).
- Library browse + LIKE filter; reader UI for PAGE_FLIP.

### Design gates

- All M0 doc gates merged (hard precondition).
- No new design decisions should be needed mid-M1; if one appears, that's a signal 01–03 have another gap — file it, don't improvise.

### Exit criteria

- The 9 acceptance criteria in 10 §6 pass, including the crash-mid-import test and the two performance bounds.

### Risks

- *Order-completeness validation feels too strict in practice* (VALIDATION_ERROR on incomplete active orders). If real imports trip it, the fix is in import-order materialization, not in weakening the reader rule — the rule is the design (SUMMARY #10).
- *Electron file-access ergonomics* vs the importer sandbox contract. Resolve in favor of the sandbox; convenience holes here become permanent.

---

## M2 — Organize: Collections, Tags, Local Search

**Goal**: A library of 500+ imported items stays navigable. First quality-of-life release.

**Idea**: These are the features whose absence users notice the day after import works. They are all local, all low-risk, and they generate the *data* (collection membership, tag assignments) that M6's recommendation engine will later feed on — shipping them early lengthens the signal-collection runway for free.

### Deliverables

1. **Collections**: UC-COL-001/002/003/003b/004 complete; `user_collections` + `user_collection_items` migrations; manual reorder with atomic sortIndex rewrites; collection cover from StorageObject.
2. **Tags**: `canonical_tags`/`source_tags`/`user_tags`/`content_user_tags` migrations; tag assignment UX; canonical taxonomy browse; import-time source-tag capture (mapping table populated even before mapping UX exists).
3. **Local search**: `content_title_fts` (FTS5) + query expansion via `expandSearchQuery` (zh variants); UC-013 subset (title + tag filter); saved-searches deferred.
4. Second content profile: `webtoon` (SCROLL reader mode) — cheapest proof that ContentProfile switching works.

### Design gates closed in M2

| Finding | Why here |
|---|---|
| N9 | Implement `userRating` filter semantics from the corrected search grammar |
| Prior #4 (installment) | `content_title_fts`, `saved_searches`, `search_history` DDL consolidate into 02 when created |

### Exit criteria

- 1k-content library: collection ops feel instant; tag filter + title search return in `<` 100 ms; zh-HK query finds zh-CN-titled content via expansion.

---

## M3 — Go Online: Plugin Pipeline & Remote Sources

**Goal**: Install a provider plugin from a repository, browse a remote source, read online, download for offline. This is the milestone where Venera becomes *Venera*.

**Idea**: The two hardest open problems land together because they are two halves of one promise: *safely acquire the code* (08's install pipeline — the project's largest security surface) and *safely acquire the content* (N8's unit materialization — the project's largest design gap). Neither can be "iterated into" later without migration pain, so both get their full design closed before code starts. This milestone has an explicit **design sub-phase (M3.0)** for that reason.

### M3.0 Contract application sub-phase (blocking)

> **Account/security gates proposed 2026-10-09 (not adopted yet):** before implementing M3 providers, define first-class SourceInstance + ExternalAccountProfile within the **initial fresh-v2 schema**, Account-bound DownloadTask, host-only login and account UI, typed capability RPC, per-platform Vault isolation, and source-scoped request auth. Do **not** treat `provider.login(credentials)`, `api.fetch(RequestInit)` or old source-runtime code as required compatibility constraints. Hosted Venera passkey registration belongs to M4 auth, distinct from a third-party website's actual login capabilities.

| Finding | Contract to implement |
|---|---|
| **N8** | `UC-REMOTE-001: Materialize Remote Section Units` — lazy/eager trigger, provenance matching, reconcile-never-renumber, null-storage remote fetch path |
| **N4** | Storage-plugin registration rule: `backend_kind='plugin'` + `plugin_key` column + uninstall-disables-backends lifecycle |
| **N11** | `plugin_reader_modes` PK `(plugin_key, mode_id)`; pair-reference rule |
| **N20** | State-machine split: artifact states (08 authority) vs runtime states (`installed_plugins`) |
| **N7** | Proposal-table constraints and insert-or-skip writer behavior with the relationship tables' migration |
| **N19** | download_tasks `SET NULL` + cancel-on-source-delete rule |

### Deliverables

1. **Install pipeline (P4, 08 authority)**: repository client → download → integrity+signature verifier → PackageStore (commit/active/orphaned/cleanup, lease timers, owner token) → source_platform mutation. `source_repositories` + `source_package_artifacts` + `installed_plugins` migrations. Official repo only at first; community/custom tiers behind a flag until the verifier has soak time.
2. **Plugin runtime (full isolation)**: WorkerPool, PluginProxy with the complete 05 enforcement chain (scheme allowlist, SSRF/public-address pinning, manual redirect re-validation, size cap, rate limits, audit of fetches into diagnostics for now).
3. **Provider SDK surface**: `defineProvider` end-to-end with one official provider plugin as the reference implementation.
4. **Remote reading**: UC-REMOTE-001 implemented; OpenReader remote branch; source-link management UCs (UC-SRC-001/002/003) promoted from Planned Canonical to implemented.
5. **Downloads**: download_tasks + queue + UC-DL-001..007, CAS status transitions, per-unit transactions, resume-recomputes-counters.
6. **Update checks**: content_update_schedules + hourly job + new-section detection (notifications themselves are M5; M3 records results and badges counts).

### Exit criteria

- Fresh install → add official repo → install provider → search remote → read online → save position → download 3 sections → airplane mode → still readable, position still resumes.
- Security: SSRF test suite passes (redirect-to-localhost, DNS-rebind, file:// scheme, oversized body); a tampered archive fails closed at verify; an unverified artifact can never reach `active`.
- Crash mid-install at every boundary (post-download / post-verify / post-commit) recovers per 08's lease rules — resumed or orphaned, never stuck, never half-active.

### Risks

- **Scope gravity.** This is the largest milestone; the flag-gated community tier and deferred notification UX are the pressure valves. Cut breadth (one provider, one repo) not depth (never ship a partial verifier).
- N8's reconcile rules will meet hostile real-world data (providers reordering chapters). The never-renumber guarantee must win every tie; log reconcile anomalies to diagnostics from day one.

---

## M4 — Hosted Mode: Auth, API, Admin

**Goal**: `docker run venera` — a self-hosted instance with passkey login serving the same library UX over the web. (Parallel-safe with M5.)

**Idea**: Hosted mode is deliberately late: every core contract it exposes was already proven standalone, so this milestone is *pure adapter work* plus the auth domain — exactly what the ports architecture promised. Doing auth after the plugin pipeline also means the audit-worthy events (installs, fetches) already exist to be audited.

### Deliverables

1. **P2 API layer**: `@venera/api` defineRoute/defineRouter, full middleware pipeline (Correlation → Security → Auth → RateLimit → Validation → Audit), adapter-express (or hono — one, not both), OpenAPI generation, `@venera/client`.
2. **P3 auth**: auth tables migration; passkey (@simplewebauthn) + local_password (argon2id) first; OAuth (arctic) + API keys + ws_tickets next; selector/verifier token scheme with **key_id from day one** (N17).
3. **Setup & admin pieces**: first-run wizard with setup token; user management (owner/admin/viewer roles via PolicyEngine); rate limits per 04's table.
4. **Audit log v1**: append-only `audit_events` with hash chain (external checkpointing deferred to M7); auth + plugin.install streams first.
5. Web client shell (thin — same use cases over the API client).

### Contract gates implemented in M4

| Finding | Implementation gate |
|---|---|
| **N17** | Apply HMAC key_id + rotation contract before the first token is ever issued, so no migration of live credentials is ever needed |

### Exit criteria

- Two browsers, one instance: register via passkey, both read the same library; viewer role cannot mutate content (SCOPE_DENIED path tested); revoking an API key kills it immediately; rotating the HMAC key invalidates nothing that shouldn't die.
- Rate-limit and auth middleware measured `<` 2 ms combined overhead per request.

### Risks

- Multi-user semantics of a formerly single-user library (whose reading position? whose collections?) — v2 core deliberately has no user domain model. M4 scope: **single-library, role-gated** (owner's library, viewers read). Per-user positions/collections are a *future contract*, flagged now, not improvised here (same discipline as D19's sync gating).

---

## M5 — Daily-Driver Features

**Goal**: The features that make Venera the app someone opens every day: notifications, reading stats, backup, parental controls. (Parallel-safe with M4.)

### Deliverables

1. **Notifications**: notifications table + UC-NOTIF-001..005 + preferences; wire M3's update-check results and download completions into real notifications (in-app first; OS push per-platform after).
2. **Reading stats**: `reading_stat_entries` (with `anonymous_session_id` per N2's M0 rename) + reading_streak + UC-STAT-001..003; async recording, never blocks the reader (the 09 best-effort rule applies).
3. **Backup/restore**: UC-BACKUP-001/002 with the **N13 identity ladder** (sourceLinks → fingerprints → title-as-candidate-with-decision, default keep_both); manifest includes sourceLinks + fingerprints; restore is dry-run-first (show the match plan before writing).
4. **Parental controls**: content_filter_profile + `content_rating` column (per N5's unified scale), fail-closed unrated rule, argon2id PIN.
5. Remaining importers by demand (pdf, epub → unlocks `document`/`novel` content types and TEXT_FLOW/PDF reader modes).

### Design gates closed in M5

| Finding | Why here |
|---|---|
| **N13** | Restore matcher ladder — implemented, with the merge-corruption test as its acceptance test |
| N5/N2 | Already fixed on paper in M0; the columns/enums ship here |

### Exit criteria

- Backup on machine A → restore on machine B → positions, collections, tags, ratings intact; a same-title-different-work pair restores as two contents (keep_both), **never** merged.
- Filter enabled + PIN: explicit and unrated content invisible in browse/search/collections alike; disable requires PIN.
- A month of simulated reading generates correct streaks across a timezone change.

---

## M6 — Recommendation & Discovery

**Goal**: The library starts giving back: related content, duplicate detection, semantic search.

**Idea**: Strictly phased exactly as 06 lays out — graph before CF before ML — because each phase is useful alone and each later phase needs the earlier one's data to evaluate against. By now M2 (collections/tags) and M5 (stats) have been generating training signal for months; this ordering was deliberate.

### Deliverables

1. Relationship/proposal/fingerprint/vector migrations (with N7's constraints, if not already landed in M3); ContentRelationship CRUD + proposal review UX (accept = same-transaction relationship write, per 01 §22).
2. **Phase 1**: fingerprint computation (pHash/dHash on covers, structure counts); duplicate detection surfacing proposals; graph walk + ContentRank over the relationship graph.
3. **Phase 2**: collection co-occurrence CF + reading-sequence item-item CF; `reading_events` + `recommendation_feedback` capture.
4. **Phase 3** (flag-gated): sqlite-vec / pgvector setup; title embeddings (multilingual-e5-small); two-tower ranking per 06's weights; semantic search joins UC-SEARCH ranking.
5. Privacy rails verified: all training local/per-instance; k-anonymity ≥ 5 on any community aggregate; TIER rules on every new payload.

### Exit criteria

- Import an obvious duplicate → proposal appears with sane confidence; accepting creates the directed edge and both directions query correctly (3b semantics).
- "Related" shelf populated from graph+CF alone (Phase 3 off) is already non-embarrassing — that's the bar for shipping the flag off.
- Vector `signalVersion` bump correctly invalidates and rebuilds (01 §24 fail-closed rule tested).

---

## M7 — Observability & Hardening

**Goal**: Operable by strangers: self-hosters get real signals; the audit chain becomes tamper-evident end-to-end; performance is characterized, not guessed.

### Deliverables

1. Audit chain completion: external checkpoint store (separate DB per 02), merkle roots, verification CLI (`venera audit verify`).
2. OTel export wiring: logs → Loki, metrics → Prometheus, traces → Tempo; pre-approved attribute keys only; TIER-0 leak test in CI (grep exported payload schemas against the forbidden-field list).
3. Crash reporting + community telemetry behind TelemetryConsent flow (consent rows versioned per 02's rule).
4. Diagnostics retention/pruning policy for `diagnostics_events` (bounded store promise in 09 becomes enforced, not aspirational).
5. Load characterization: 10k-content library benchmark suite; plugin worker memory ceilings; download queue saturation behavior.

### Exit criteria

- Deleting a mid-stream audit row is detected by `venera audit verify` (seq gap + prevHash + checkpoint mismatch — all three tripwires fire).
- A self-hoster following the docs gets dashboards showing request rate, error rate, plugin fetch health with zero TIER-0 fields anywhere in the pipeline.
- Benchmark suite runs in CI with regression alerts on the M1 performance bounds.

---

## Findings → Milestone Ledger

Every finding, where its corrected contract is implemented and tested:

| Finding | Closes in | Form |
|---|---|---|
| N1, N2, N3, N5, N6, N12, N14, N15, N16, N18 | **M0** | doc edits + CI guards |
| N9 | **M2** | userRating search filter implementation |
| N4, N7*, N8, N11, N19, N20 | **M3** (M3.0 contract application) | migrations + runtime behavior |
| N17 | **M4** | key_id + rotation implementation, before first token |
| N13 | **M5** | restore identity ladder implementation |
| N7* | M3 or **M6** | lands with whichever milestone creates the relationship tables |
| N10 | **M2/M5/M6** piecemeal | deferred stubs become full entity+DDL blocks in the milestone that implements them; ports not reached by M6 get deleted from the aggregate |
| Prior #4 (consolidation) | **every milestone** | standing rule: any DDL a milestone creates moves into 02 in that milestone's PR; 05/07 fragment blocks shrink to cross-references as they consolidate |

\* N7 appears twice deliberately — the constraint design is written in M3.0; the migration ships with the tables.

---

## Standing Rules (all milestones)

1. **No code against an open contract.** If a milestone needs a decision the docs don't contain, the milestone stops and the doc gets the decision first. (This is how the findings list stops growing.)
2. **Consolidate as you create** (prior #4): new tables land in 02, not in feature docs.
3. **Every invariant a milestone touches gets a test named after it.** The SUMMARY's 34 invariants are the checklist; by M7's end, all 34 have a named test or a documented reason they can't.
4. **Status labels move only forward** (`Planned Canonical → Target → Implemented (Core+DB)`), and only in the PR that ships the implementation — the docs stay honest about what exists.
5. **Cut breadth, not depth.** Fewer providers/importers/formats is always acceptable; a partial verifier, a weakened sandbox, or a skipped reconcile rule never is.
