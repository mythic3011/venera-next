# Design v2 Review — Findings & Fixes (2026-07-02)

**Reviewer**: Cowork design review pass (third pass)
**Scope**: All 10 design files in `docs/design/v2/` + cross-document consistency.
**Prior passes**: `CLAUDE_HANDOFF.md` (00/05/06/07), `REVIEW_HANDOFF.md` (01/02/03/04/08/09, triaged by `CODEX_TO_CLAUDE_HANDOFF.md`).

Severity key (same as prior pass): **BREAK** = invariant violation or silent data corruption path; **GAP** = missing contract that blocks correct implementation; **DRIFT** = entity ↔ DDL or cross-doc inconsistency; **NOTE** = design tension worth a decision, not necessarily wrong.

Each new finding carries three fields:
- **Idea** — the design principle at stake and why the current text is a problem.
- **Direction** — the recommended approach, including alternatives when the choice is genuinely open.
- **Fix** — the concrete minimal edit.

---

## Part 1 — Prior Findings Verification

18 of 19 findings from `REVIEW_HANDOFF.md` are resolved in the current docs. Verified:

| Prior # | Status | Where fixed |
|---|---|---|
| 1a StorageBackend `plugin` kind | ✅ Fixed | 01 §14 + validation rules |
| 1b `illustrated` ContentProfile | ✅ Fixed | 04 ContentProfiles |
| 2a Cover-unit deletion rule | ✅ Fixed | 01 §2 invariants; 02 comment; 03 Transaction Semantics #7 |
| 2b UC-003 title / denormalized cache | ✅ Fixed | 03 UC-003 step 2 (fails closed when no primary title) |
| 3a Recommendation entity specs | ✅ Fixed | 01 §21–24 |
| 3b Relationship directionality | ✅ Fixed | 01 §21 (directed evidence, no implicit reverse edge); 02 notes |
| 3c ImportJob entity contract | ✅ Fixed | 05 "ImportJob Entity Contract" |
| 4 Schema consolidation (~15 tables) | ⚠️ Still open (tracked debt) | 02 header + 05/07 "target fragments" banners — by design, close during implementation |
| 5a Redundant audit index | ✅ Fixed | 02 (only `idx_audit_stream_seq` + `idx_audit_recorded_at` remain) |
| 5b content_titles logical unique | ✅ Fixed | 02 `ux_content_titles_logical` with COALESCE sentinels |
| 5c reading_events session_id rename | ✅ Fixed | 02 `anonymous_session_id` + index — **but see N2: 07 regressed** |
| 6a Deferred CRUD appendix | ✅ Fixed | 03 "Deferred CRUD / Management Use Case Appendix" |
| 6b UC-011 container-kind validation | ✅ Fixed | 03 UC-011 step 3 |
| 7a zh-TW converter | ✅ Fixed | 04 `expandSearchQuery` (product decision zh-TW→zh-HK still open, noted inline) |
| 7b OpenCC lazy init | ✅ Fixed | 04 `getChineseConverters()` |
| 8a PolicyEngine startsWith | ✅ Fixed | 04 `ADMIN_EXCLUDED` exact-match set |
| 9 Activation lease renewal | ✅ Fixed | 08 (owner token, 2-min heartbeat, 30-min max window) |
| 10a Removal event families | ✅ Fixed | 09 (`collection.item_removed`, `source_link.removed`, `section_source_link.removed`) |
| 10b Schema evolution policy | ✅ Fixed | 09 header policy |

---

## Part 2 — New Findings

> **Status update 2026-07-03**: The M0 doc-fix batch (N1, N2, N3, N5, N6, N12, N14, N15, N16, N18 — see `11_MILESTONES.md` § M0) has been **applied** to docs 01/02/04/05/06/07/09. Remaining open: N4, N7, N8, N11, N19, N20 (close in M3.0), N9 (M2 decision), N10 (piecemeal), N13 (M5), N17 (M4), prior #4 (standing rule).

> **Status update 2026-07-07**: The remaining design-contract findings have now been applied to the canonical docs: N4, N7, N8, N9, N10, N11, N13, N17, N18 hardening, N19, and N20. Milestone docs now treat these as implementation gates rather than unwritten design gaps. Prior finding #4 (schema consolidation into 02 as feature tables land) remains standing tracked debt.

### N1. Event name split: `content.metadata_updated` vs `content.updated` (DRIFT)

- **04_PACKAGES_AND_PIECES.md** `ContentEvents.METADATA_UPDATED = "content.metadata_updated"`.
- **03_USE_CASES.md** UC-003 emits `content.updated`; **09_OBSERVABILITY.md** defines `content.updated`.
- **Idea**: 04 declares itself "single source of truth for all event names — never use raw strings". A single-source-of-truth constant that disagrees with the docs that consume it is worse than no constant: an implementor typing `ContentEvents.METADATA_UPDATED` will emit an event that 09's readers and any dashboards keyed on `content.updated` never see. Event names are a wire contract — split names silently split the audit/diagnostics stream.
- **Direction**: Standardize on `content.updated` (two docs already use it; UC-003 updates more than metadata — cover refs and primary title — so the broader name is also more accurate). If a distinct metadata-only event is ever wanted, add it *alongside* later, don't overload now. After fixing, treat 04's constants file as generated-from or checked-against 09's event families in CI so this class of drift can't recur.
- **Fix**: Rename 04's constant to `UPDATED: "content.updated"`, grep 03/09 for other strays.

### N2. `ReadingStatEntry.sessionId` — entity ↔ DDL drift + regression of prior fix 5c (DRIFT)

- **07_FEATURES.md** entity declares `sessionId: String -- anonymous, rotates daily`; the `reading_stat_entries` DDL in the same file has **no session column at all**. **06** Privacy TIER 2 also still says `sessionId`.
- **Idea**: Two problems layered. (1) Entity ↔ DDL disagreement means one of them is fiction — stats aggregation code written against the entity will query a column that doesn't exist. (2) The name `sessionId` collides with `ReadingSession.id`, which is exactly why prior pass 5c renamed the same concept to `anonymous_session_id` in `reading_events`. Same concept, two names across tables re-creates the confusion the rename was meant to kill. The privacy design (daily-rotating anonymous token) only works if every consumer knows it is *not* a ReadingSession reference.
- **Direction**: One vocabulary for one concept: `anonymous_session_id` everywhere (02 `reading_events`, 07 `reading_stat_entries`, 06 tier list). Then decide whether stats actually need the token: it exists to group same-day entries without identity. If per-day grouping via `session_date` is sufficient, drop the field from the entity instead of adding the column — fewer pseudo-identifiers is strictly better for privacy.
- **Fix**: Rename in 07 entity + 06 TIER 2; add `anonymous_session_id` to the DDL *or* delete the field from the entity — they cannot both stay as-is.

### N3. Three inconsistent plugin manifest shapes (DRIFT)

- **05** `PluginManifest` ("Complete") has no `providerKey`, `archiveSha256`, `pluginLayer`; **06** "Required Fields" requires all three; **01** `SourcePackageManifest` uses `packageKey` + `providerKey` + `archiveSha256`.
- **Idea**: The manifest is the contract between plugin authors, the verifier, and the installer. Three shapes means the Zod schema in `@venera/schema` has no authority to implement from. Worse, `archiveSha256` placement is a *security* question, not a formatting one: a hash **inside** the archive can't protect the archive that contains it (self-referential), while 08's trust chain correctly verifies "archiveSha256 against **signed index entry**". If the manifest carries the field, implementors may be tempted to trust the wrong copy.
- **Direction**: Make 05 the single manifest authority; reduce 06's block to a cross-reference. Resolve fields on principle: `archiveSha256` belongs to the signed repository index/package entry, **not** the manifest — remove it from 06's manifest list. `providerKey` and `pluginLayer` are real contract facts (identity metadata; SDK tier affects sandbox/validation policy) — add them to 05's manifest. Align vocabulary with 01: decide `key` vs `packageKey` once and note the mapping in SUMMARY's naming table.
- **Fix**: Edit 05 manifest (+`providerKey`, +`pluginLayer`), rewrite 06's manifest section as a pointer to 05, delete `archiveSha256` from manifest-level fields, add a one-line note that archive hashes live only in signed index entries (08 authority).

### N4. `storageConfig.backendKindKey` contradicts the `backend_kind` CHECK constraint (DRIFT → would be BREAK at runtime)

- **05** storage plugin config: `backendKindKey: string // used as backendKind in StorageBackend`. **02**: `CHECK (backend_kind IN ('local_app_data','webdav','plugin','future'))`.
- **Idea**: The CHECK enum embodies a deliberate design: `backend_kind` is a *runtime dispatch category* (which code path handles this backend), not an open plugin namespace. Letting plugins inject arbitrary kind values would turn a closed enum into an uncontrolled registry and break every `switch` on kind. The plugin's own identity already has a home — that's what `kind = 'plugin'` exists for. As written, though, the two docs are on a collision course: any storage plugin install throws a CHECK violation, so the feature is dead on arrival.
- **Direction**: Keep the enum closed (that's the right call). Storage plugins always register `backend_kind = 'plugin'`; the plugin-specific type lives in plugin-owned space — either encoded in `backend_key` (e.g. `plugin:s3:<instance>`) or as an explicit `plugin_key` column on `storage_backends` (nullable, required when kind='plugin'). The explicit column is cleaner: it keeps `backend_key` a pure unique identifier and makes "which plugin owns this backend" queryable for uninstall cleanup (when a storage plugin is removed, its backends must be found and disabled — a real lifecycle need).
- **Fix**: 05: rename/redocument `backendKindKey` → plugin storage type metadata; 02: add nullable `plugin_key` to `storage_backends` with a comment `NOT NULL when backend_kind='plugin'`; add the uninstall-time "disable owned backends" note to the plugin lifecycle in 05.

### N5. `content_rating` column not reflected in 01's ContentMetadata entity (DRIFT)

- **07** adds `ALTER TABLE content_metadata ADD COLUMN content_rating ...`; **01** ContentMetadata entity has no such field. `maxContentRating` enum `(all|safe|moderate|adult_only)` vs `ContentRating` `(safe|moderate|adult_only|explicit)`; `max_content_rating` column has no CHECK.
- **Idea**: 01 is the declared entity authority — a feature doc ALTERing an authority-owned table without the entity knowing is exactly how "entity ↔ DDL mismatches" (prior findings 1a/1b) are born. Separately, a filter ceiling and a rating label must share one ordered scale, or the comparison `rating <= max` is undefined: with the current enums, what does `max = adult_only` say about `explicit` content? The answer is guessable, and parental controls must never rest on a guess — this filter is a child-safety surface, ambiguity here fails in the worst direction.
- **Direction**: Define one ordered scale once: `safe < moderate < adult_only < explicit`, and express the ceiling in the same scale (`maxContentRating ∈ scale ∪ {all}` where `all` ≡ no ceiling, or just use `explicit` as the permissive top and drop `all`). Filtering rule stated explicitly: content with **no** rating is treated as *most restricted* when filtering is enabled (fail closed — unrated content hides when parental controls are on). Add `contentRating` to 01 as an optional feature-domain field marked Target, keeping 01's authority intact.
- **Fix**: 01: add `contentRating` (optional, Target); 07: align both enums to one scale, add CHECK on `max_content_rating`, add the fail-closed unrated rule.

### N6. `content_fts` defined in both 02 and 07 (DRIFT)

- 02 owns `content_fts` canonically; 07 redefines the identical table. `content_title_fts` exists only in 07 (legitimately pending consolidation).
- **Idea**: The "target fragments" banner exists to cover *not-yet-consolidated* tables. A table that already lives in 02 but is re-declared in 07 defeats the single-authority rule silently: the next person to edit tokenizer settings will edit one copy and the two will diverge without any conflict signal.
- **Direction**: The rule should be mechanical: a `CREATE TABLE` may appear in exactly one file; every other mention is a link. When consolidating 07's tables into 02 (prior finding #4), move `content_title_fts` in and delete the `content_fts` duplicate in the same edit.
- **Fix**: Replace 07's `content_fts` block with "see 02 § Misc tables".

### N7. `content_relationship_proposals` DDL missing constraints the entity requires (GAP)

- No `CHECK (source != target)`, no `confidence` CHECK, no dedup rule for `pending` proposals; nothing names an app-layer guard.
- **Idea**: Proposals are written by the *automated* recommendation path — the highest-volume, least-supervised writer in the system. That's precisely where DB-level constraints earn their keep: a bug in a scorer loop should produce constraint errors, not thousands of duplicate pending rows that then flood the review UI. The entity invariants in 01 already state the rules; a stated invariant with no enforcement point is a wish, not a contract (same principle as prior finding 5b).
- **Direction**: Enforce cheap structural rules in DDL (self-reference CHECK, confidence CHECK — both free). For dedup, use a partial unique index `(source_content_id, target_content_id, suggested_type) WHERE status = 'pending'` — this allows re-proposing after a proposal expires/rejects (which is desired: new evidence may appear later) while blocking concurrent duplicates. The proposal writer should upsert-or-skip on conflict, not error.
- **Fix**: Add both CHECKs + the partial unique index to 02; note the writer's on-conflict-skip behavior in 06's recommendation section.

### N8. Remote-content ContentUnit creation pipeline is undefined (GAP)

- **07** UC-DL-002 says "update `ContentUnit.storageObjectId`" — assumes unit rows exist. Update-check creates sections + section source links only. No use case anywhere materializes `provider.getUnits()` results into ContentUnit rows.
- **Idea**: This is the largest genuinely missing design piece. The whole reader stack (OpenReader, ReadingSession position authority, ContentUnitOrder completeness validation) is built on canonical unit rows — `unitId` **is** the position authority. If remote reading doesn't materialize units, saved positions for remote content are impossible and OpenReader has nothing to resolve; if it does, *when* and *how* units materialize decides correctness under remote change (a provider re-ordering or re-hosting pages must not corrupt saved positions). Leaving this implicit guarantees each implementor invents a different answer.
- **Direction**: Materialize-on-first-need, reconcile-by-evidence:
  1. **Trigger**: units for a section are materialized lazily on first open of that section (online reading) and eagerly during download preflight (UC-DL-002 step 1). Browsing a section list never materializes units.
  2. **Identity**: a materialized unit's provenance is `(sectionSourceLinkId, source position/url evidence)`; `unitIndex` is assigned from the provider's order at materialization time. `unitId` stays a fresh UUID — provider URLs are *evidence*, never identity (same principle as SourceLink).
  3. **Reconcile**: on re-fetch, match existing units by provenance evidence; append new units; never renumber or delete units that a ReadingSession references — mark them stale/orphaned instead (mirrors the "stale source context never invalidates a saved unit" session rule).
  4. **No storage yet**: materialized-but-not-downloaded units have `storageObjectId = null`; the reader's remote fetch path serves bytes via PluginProxy. This slots into the existing "ContentUnit Asset Availability" rules in 03 — `null` storage + active remote provenance = deliberate remote fetch, exactly as that section already hints.
- **Fix**: Add a `UC-REMOTE-001: Materialize Remote Section Units` contract (03 or 07) covering trigger, provenance matching, reconcile rules, and the never-renumber guarantee; reference it from UC-DL-002 step 1 and from OpenReader's remote branch.

### N9. Search `rating` filter references a field that does not exist (GAP)

- **07** search grammar has `rating:>=4` and `SearchFilter.rating { gte, lte }`; backup export mentions "ratings". No numeric rating field exists anywhere (N5's `content_rating` is categorical, not numeric).
- **Idea**: A filter over a nonexistent field is a spec that cannot be implemented, and it smells like a copied-in feature from another reader app's search grammar. Personal star ratings are a real, reasonable feature for a library app — but it's a *product decision* (entity + column + UC + backup inclusion), not something to back-fill because the search grammar mentioned it.
- **Direction**: Decide the product question first: does Venera want per-content user ratings (1–5 stars)? If yes: add `userRating: Integer (1..5, optional)` to ContentMetadata in 01 + DDL + a metadata-update path via UC-003, then the filter is honest. If no: delete `rating:` from the grammar, `rating` from SearchFilter, and "ratings" from the backup manifest. Do not leave the filter as aspiration — every dangling reference in the "complete" search design costs the next reader trust in the rest of it.
- **Fix**: One of the two edits above; recommend deciding at the same time as N5 since both touch ContentMetadata.

### N10. CoreRepositories references ports for entities that are specified nowhere (GAP)

- **07** `CoreRepositories` includes `smartCollections`, `creators`, `sourceCreators`, `contentCreators`, `readerSettings`, `colorPalettes` — no entity or DDL for any of the six anywhere. Backup export also references `ContentCreator` and `UserReaderPreferences`.
- **Idea**: The aggregate interface is the *implementation checklist* — an implementor walks it port by port. Ports with no backing spec force one of two bad outcomes: invented ad-hoc schemas (exactly what the v2 rewrite exists to prevent), or silently skipped ports that later break the backup format which references them. The Creator domain especially is non-trivial (creator identity vs source-creator provenance mirrors the Content/SourceLink split) and deserves a real design, not an implied one.
- **Direction**: Follow the pattern the docs already use for Favorites: keep the ports but mark them explicitly, and give each a minimal home. Creator domain: a short entity block (Creator + SourceCreator + ContentCreator, deliberately mirroring Content/SourceLink/provenance principles) marked Planned Canonical. SmartCollection, ReaderSettings, ContentColorPalette: either one-paragraph Deferred stubs in 07 stating intent, or removal from the aggregate until designed. Backup manifest may only list entities that have at least a stub.
- **Fix**: Annotate the six ports with status labels; add stubs or remove; reconcile the backup manifest list.

### N11. `plugin_reader_modes.mode_id` is a global primary key (GAP, security-adjacent)

- **05** DDL: `mode_id TEXT PRIMARY KEY`, but `modeId` is chosen by the plugin author.
- **Idea**: Any identifier chosen by an *untrusted* party must be namespaced by the trusting party — otherwise first-come-first-served becomes an attack surface: a malicious plugin pre-claims `"vertical_novel"` and either blocks the legitimate plugin's install or, worse, gets *its* sandboxed iframe URL served where the user expected the other plugin's reader. This is the same principle the design already applies elsewhere (`providerKey` is "identity metadata only", plugin permissions are validated subsets) — plugin-declared strings never become global authority raw.
- **Direction**: Composite key `(plugin_key, mode_id)` as PK, and every runtime reference to a reader mode carries both halves (content profile overrides, user preferences pointing at a plugin reader must store `pluginKey + modeId`). Display-name collisions between plugins are then a pure UI concern (show publisher), not an identity concern. Uninstall cascade already works via the existing FK.
- **Fix**: 05 DDL: `PRIMARY KEY (plugin_key, mode_id)`; note that mode references elsewhere are the pair, never the bare `modeId`.

### N12. ImportJob cannot be cancelled while `pending` (GAP)

- **05** ImportJob: flow `pending -> running -> completed | failed | cancelled`; "`startedAt` present for `running`, `completed`, `failed`, `cancelled`".
- **Idea**: A queue with no dequeue is a design hole users hit immediately (queued the wrong folder, want it gone before it runs). The two stated invariants also contradict each other for that case — cancel-from-queue would have to fabricate a `startedAt` for a job that never started, corrupting duration stats and audit honesty.
- **Direction**: Model it like DownloadTask already does (cancel from `queued` is implied there): allow `pending -> cancelled` directly. `startedAt` means "entered running" and nothing else; a pending-cancelled job has `startedAt = null`, `completedAt = <cancel time>`. Keep terminal-states-are-terminal.
- **Fix**: 05: add `pending -> cancelled` to the flow; reword invariant to "`startedAt` is present iff the job has entered `running`".

### N13. Backup restore matches content by `normalizedTitle + contentType` (NOTE — tension with core invariant)

- **07** UC-BACKUP-002: "Content matched by normalizedTitle + contentType".
- **Idea**: Invariant 1 — "`normalizedTitle` is never identity" — is the load-bearing wall of the whole identity design, and restore is the one flow where getting it wrong is *destructive at scale*: a merge-mode restore silently fuses two distinct works (same title, different works — explicitly a supported situation), mixing their sections, sessions, and collections with no undo. The invariant exists precisely because titles collide; restore can't be the sanctioned exception.
- **Direction**: Identity-evidence ladder, strongest first — the same shape the import preflight already uses: (1) SourceLink `(sourcePlatformId, remoteWorkId)` pairs from the backup (exact, unique, cheap); (2) ContentFingerprint `externalIds` / hashes; (3) `normalizedTitle + contentType` only as a *candidate* generator that yields a duplicate-decision (`merge | keep_both | skip`) — defaulting to `keep_both` in merge mode, because a wrong keep-both is recoverable and a wrong merge is not. Backup export must therefore include source links and fingerprints (it already includes relationships; add these).
- **Fix**: Rewrite UC-BACKUP-002's matching rule as the ladder; add `sourceLinks` + `contentFingerprints` to the UC-BACKUP-001 manifest.

### N14. EhViewer importer example contradicts stated invariants (NOTE — doc example only)

- `canHandle` checks extension only while invariant 31 requires magic numbers (the comment even quotes the SQLite magic it doesn't check); `ctx.utils.querySqlite` is not in the `ImporterUtils` interface; yields placeholder `contentId: "new"`.
- **Idea**: Example code in a design doc *is* spec by imitation — community importer authors will copy this file verbatim as their template. An example that violates the doc's own invariant 31 teaches the violation. And `querySqlite` appearing only in an example means a real, security-relevant capability (sandboxed SQLite over user files) exists with no declared contract for its sandbox rules.
- **Direction**: Treat examples as conformance tests for the SDK contract: fix the example to check magic bytes via `ctx.utils.detectFileType` (which exists), promote `querySqlite(path, sql): Promise<Row[]>` into `ImporterUtils` with an explicit note that it is read-only and confined to the import-source sandbox (same realpath rules as `handleFileRead`), and use `registerContent`'s return value for the result event.
- **Fix**: Three small edits in 05 as above.

### N15. `recommendation_feedback` has no FK constraints (NOTE)

- `source_content_id`/`target_content_id` lack `REFERENCES contents(id)`, unlike every other content-referencing table.
- **Idea**: Both readings are defensible — training signals arguably *should* survive content deletion (the pattern "user dismissed this pairing" stays informative), and FK-less telemetry tables are a common pattern. But in a schema where every neighbor has FKs, an unexplained exception reads as an accident, and the next tidy-minded editor will "fix" it, silently changing retention semantics.
- **Direction**: Decide by data purpose: these rows are *behavioral evidence*, not referential state — keep them FK-free, and say so in a one-line comment (`-- intentionally no FK: feedback evidence outlives content deletion`). Consistent with `training_signals` which is also FK-free. If instead the team wants strict referential hygiene, use `ON DELETE CASCADE` and accept losing negative-pair history.
- **Fix**: Add the intent comment (recommended), or add FKs — either way, make it deliberate.

### N16. `content_annotations` offsets forced NOT NULL for bookmarks (NOTE)

- `start_offset`/`end_offset` are `NOT NULL`, but `annotation_type = 'bookmark'` on an image unit has no meaningful text offsets.
- **Idea**: A NOT NULL column that some rows can't honestly fill breeds sentinel garbage (`0`/`-1`) that later code must know to ignore — un-typed knowledge, the thing schemas exist to eliminate. Highlights/comments genuinely need offsets; bookmarks are unit-level marks.
- **Direction**: Nullable offsets + a CHECK expressing the real rule: `CHECK (annotation_type = 'bookmark' OR (start_offset IS NOT NULL AND end_offset IS NOT NULL))`, plus `CHECK (end_offset >= start_offset)` while touching it. Alternative (splitting bookmarks into their own table) is cleaner relationally but not worth the extra port/UC surface for one type.
- **Fix**: 02: relax NOT NULL, add both CHECKs.

### N17. Auth-token HMAC server key lifecycle unspecified (NOTE — security)

- 02/06 specify `HMAC-SHA256(verifier, serverKey)` but nothing defines where `serverKey` lives, no key id on hashes, no rotation contract. Audit events carry `signing_key_id`; token hashes carry nothing.
- **Idea**: A pepper you can never rotate is a liability with a countdown: the first suspected leak forces a choice between "keep using a possibly-burned key" and "log out every user and kill every API key at once". The audit design already solved this (`signing_key_id`) — the asymmetry is an oversight, not a decision. Key identity on the hash makes rotation an *operational* task instead of an incident.
- **Direction**: Mirror the audit pattern: add `key_id` next to `token_hash`/`key_hash`; verification looks up the key by id (constant-time compare unchanged). Rotation contract: new credentials sign with the newest key; old keys stay valid for verification until their credentials expire naturally (sessions have TTLs; API keys re-issue on demand); a compromised key id can be hard-revoked, invalidating only its credentials. `serverKey` material lives behind the same `secretRef` discipline as every other secret (OS keychain / deployment secret manager) — never in DB or config files.
- **Fix**: 02: add `key_id TEXT NOT NULL` to `auth_sessions` + `api_keys`; 06: add a short "HMAC key management" paragraph with the rotation rules above.

### N18. `@venera/events` stream catalog misses events other docs emit (NOTE)

- 04's `AllEventNames` spreads 8 streams; events used elsewhere with no home: `source_link.*`, `section_source_link.*`, `sections.created`, `section.units_reordered`, `download.*`, `notification.created`, `sync.conflict`, `search.executed`, `system.*`, `security.*`.
- **Idea**: "Never use raw strings" is only enforceable if the constants file is *complete* — every missing event is a place where an implementor must either break the rule or block. The catalog and 09's event families are two views of one registry and will drift forever unless one generates or checks the other.
- **Direction**: Add the missing stream modules (SourceLinkEvents, DownloadEvents, NotificationEvents, SearchEvents, SystemEvents, SecurityEvents) using the existing pattern (constants + Zod payload schemas — the payload schemas double as the TIER-privacy enforcement point, which is the deeper value here: a payload schema that has no `title` field *cannot* leak a title, per the schema-level privacy rule). Longer term, add a CI check: every event name in 09 exists in `AllEventNames` and vice versa.
- **Fix**: 04: add six stream modules to the catalog list; 09: add `sections.created` + `section.units_reordered` to the event families.

### N19. `download_tasks.source_link_id ON DELETE CASCADE` erases download history (NOTE)

- Deleting a SourceLink (a deferred use case) cascades away completed download task rows.
- **Idea**: Task rows serve two roles with different lifetimes: *queue entries* (short-lived, source-bound) and *history/evidence* ("I downloaded these 40 chapters last month"). CASCADE conflates them — detaching a dead source silently rewrites the user's download history. The SourceLink-deletion use case is deferred, so this is exactly the kind of decision the deferred appendix exists to pin down before someone implements the FK behavior by accident.
- **Direction**: `ON DELETE SET NULL` for terminal-status tasks fits the evidence role (`plugin_key` string remains for attribution); active/queued tasks for a deleted source should be *cancelled by the deletion use case*, not cascaded away invisibly. Record this in 03's deferred SourceLink-deletion entry so the two decisions land together.
- **Fix**: 07 DDL: `ON DELETE SET NULL` (column becomes nullable); 03 deferred appendix: add "must cancel in-flight download tasks" to SourceLink deletion.

### N20. `installed_plugins.state` mixes two state machines (NOTE)

- The enum contains artifact lifecycle states (`committed`, `orphaned`, `cleanup_pending`) that 08 assigns to `source_package_artifacts.state`, plus runtime states, plus `not_installed` as a stored row value.
- **Idea**: Two tables owning overlapping state vocabularies invites the classic split-brain: artifact says `orphaned`, plugin row says `active` — which do you trust? 08 is explicit that PackageStore is the durable authority for install lifecycle; duplicating its states into `installed_plugins` creates a second authority the docs then have to keep synchronized by hand. And `not_installed` as a *stored* state inverts the meaning of row existence (absence should mean not installed).
- **Direction**: One state machine per table, joined by FK: `source_package_artifacts.state` owns acquisition (`committed | active | orphaned | cleanup_pending | removed`, per 08); `installed_plugins.state` owns runtime only (`installed | activating | active | disabled | load_error | uninstalling`), and the row is *created* at install success, *deleted* at uninstall completion. Transient acquisition states (`downloading`, `verifying`) are in-memory installer/orchestration status surfaced over WS — they don't need durable rows because crash recovery re-derives them from the artifact state + lease (08 already defines exactly that recovery). The 05 lifecycle diagram stays as the *user-facing* union view, but annotated with which table (or which layer) owns each state.
- **Fix**: 05: shrink the `installed_plugins.state` CHECK to runtime states, note row-existence semantics, annotate the lifecycle diagram with state ownership.

---

## Summary Table (new findings)

| # | File(s) | Severity | Summary |
|---|---------|----------|---------|
| N1 | 03 ↔ 04 ↔ 09 | DRIFT | `content.metadata_updated` vs `content.updated` — one event, two names |
| N2 | 07 ↔ 02 ↔ 06 | DRIFT | ReadingStatEntry.sessionId missing from DDL; regresses prior 5c rename |
| N3 | 01 ↔ 05 ↔ 06 | DRIFT | Three inconsistent plugin manifest shapes; archiveSha256 placement undecided |
| N4 | 05 ↔ 02 | DRIFT | storageConfig.backendKindKey violates backend_kind CHECK — storage plugins can't install |
| N5 | 07 ↔ 01 | DRIFT | content_rating column absent from ContentMetadata entity; rating enums misaligned |
| N6 | 02 ↔ 07 | DRIFT | content_fts defined twice; 07 copy should be a cross-reference |
| N7 | 01 ↔ 02 | GAP | proposals table missing self-ref CHECK, confidence CHECK, pending-dedup rule |
| N8 | 03 ↔ 07 | GAP | No contract creates ContentUnits from provider.getUnits (downloads + online reading) |
| N9 | 07 | GAP | Search rating filter references nonexistent field |
| N10 | 07 | GAP | CoreRepositories ports for 6 entities specified nowhere |
| N11 | 05 | GAP | plugin_reader_modes.mode_id global PK — cross-plugin collision/hijack |
| N12 | 05 | GAP | ImportJob has no pending→cancelled path; startedAt invariant contradicts it |
| N13 | 07 | NOTE | Backup restore uses normalizedTitle as identity — violates invariant 1 in spirit |
| N14 | 05 | NOTE | EhViewer example: extension-only detection, undeclared querySqlite, fake ContentId |
| N15 | 02 | NOTE | recommendation_feedback missing FKs — intentional? document it |
| N16 | 02 | NOTE | content_annotations offsets NOT NULL breaks bookmark-on-image case |
| N17 | 02, 06 | NOTE | Auth HMAC serverKey has no key id / rotation contract |
| N18 | 04 ↔ 07 ↔ 09 | NOTE | Event catalog missing streams for download/notification/search/system/security/source-link events |
| N19 | 07 | NOTE | download_tasks CASCADE on source_link_id erases history |
| N20 | 05 ↔ 08 | NOTE | installed_plugins.state duplicates artifact lifecycle authority |

---

## Recurring Themes (why these keep happening)

Reading the 20 findings together, four root patterns account for nearly all of them — worth fixing as *processes*, not just as edits:

1. **Untrusted-input-as-identity** (N11, N13, and prior 5c's collision): any string chosen by a plugin author, a provider, or a backup file must be namespaced or downgraded to evidence before it touches a primary key or a match rule. The design already states this principle for SourceLink and providerKey; apply it uniformly.
2. **Stated invariant, no enforcement point** (N7, N5's enum gap, prior 5b): every invariant in 01 should name its enforcer — a CHECK/index, or a specific use case. An invariant with neither is documentation-ware.
3. **Feature docs mutating authority-owned surfaces** (N5, N6, N2): 07's ALTERs and re-declarations bypass 01/02 authority. Rule of thumb: feature docs may *propose* columns/tables (marked Target), but the entity field list and any table already in 02 change only in 01/02.
4. **Registry completeness drift** (N1, N18, N10): "single source of truth" catalogs (event names, repository aggregate) rot unless checked against their consumers. A tiny CI script (grep event names in docs vs constants; grep ports vs entity blocks) would have caught five of these findings mechanically.

---

## Current Follow-up Order

As of 2026-07-07, the design-contract fixes for N1-N20 have been applied to the canonical docs. The follow-up order is now implementation-oriented:

1. Use `10_MVP_SCOPE.md` and `11_MILESTONES.md` as the gate map for code implementation and tests.
2. Add mechanical drift guards early: event registry completeness, repository-port/entity coverage, and authority-doc duplicate-table checks.
3. Keep prior finding **#4** as standing tracked debt: consolidate target DDL fragments from 05/07 into 02 as each feature table enters the migration baseline.
