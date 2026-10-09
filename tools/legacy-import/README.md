# Old Venera distributed-data inspector (L0)

**Status: early L0 implementation, statistics-only.** No data import, canonical DB write, account login, plugin execution or media inspection. Uses only five allowed old-Venera roles:

- `local.db`
- `history.db`
- `local_favorite.db`
- `appdata.json`
- `implicitData.json`

The old Unified Store `venera.db` is **never** an accepted import role (including when renamed, using schema detection). The *new* v2 `data/venera.db` must never be used as input.

## Run

Requires **Node >=22.16** with the experimental built-in `node:sqlite` module; no third-party runtime dependency. For the first release, run only on trusted copies or controlled test fixtures until OS-level parser sandboxing has been verified on each target platform.

```sh
node tools/legacy-import/preview.mjs --dir "/path/to/old-venera-data"
node --test tools/legacy-import/test/*.test.mjs
```

The CLI reads only the five exact basenames in the explicit directory; unknown files are ignored, not discovered or treated as a fallback. Output is **aggregate schema/count/deferred statistics** and typed error codes only. It does not expose titles, history items, usernames, URLs, raw JSON, filesystem locations or content hashes. It returns a no-input status when all five are missing.

- For SQLite input, L0 opens source via `DatabaseSync({readOnly:true})`, runs `backup()` to an app-private temporary snapshot and inspects the snapshot with `query_only` and `trusted_schema=OFF`. This includes committed WAL changes visible to SQLite; journal sidecars may be used only internally by SQLite, not as sixth/seventh metadata types. If SQLite cannot obtain a consistent backup, it rejects that role; it does not fall back to copying raw DB bytes.
- Input filenames are enforced with regular-file and symlink checks; renamed Unified Store is denied by schema signature. Signature checks are a conservative **known-variant allowlist**, not proof of harmlessness for arbitrarily crafted SQLite databases.
- `local.db` reports metadata candidates, but **no comic is called readable yet**; media-root authorization and page identity validation belong to L1.
- `history.db` positions are **review required**, never promoted to canonical ReadingSession in L0. Its `image_favorites` are counted as a distinct deferred category.
- `local_favorite.db` folder content is counted and deferred until M2; quoted dynamic SQLite table names are validated and quoted as identifiers, never accepted as SQL fragments.
- `appdata.json` has a tiny explicit typed settings-candidate whitelist, still **deferred** until an approved v2 mapping exists; unknown fields are skipped. `implicitData.json` has zero auto-importable keys at L0; all contents are skipped. This prevents session/token/source-code copying.
- A `preview_only` status is **not** approval, import, verification of media, or permission to modify anything. `canCommit` is always false. No durable Batch, Dataset, RecordMapping, Journal or Receipt exists in this L0 tool.

## Known L0 boundaries

- Parser executes locally in a Node process and **does not yet constitute an independently hardened OS sandbox**. Do not position it as safe for untrusted SQLite files on all desktop/mobile platforms. Before product UI integration, use a per-platform isolated worker process with OS-level limits/egress/filesystem restrictions and tests.
- Resource checks are bounded by per-file max bytes, per-table row count, JSON depth and node count, but `quick_check`/backup can still consume CPU on adversarial databases. OS process limits/timeout are required before shipping a general import wizard.
- This is a read-only preflight, not the L1-L3 importer. Dataset identity association, stable per-record IDs, asset-root grants, receipt journaling, storage commit, reader position reconciliation and user conflict approvals are **deliberately not implemented** here.
- Login credentials, cookies, website account profiles, legacy source JS, legacy `syncdata.json` and Unified Store are outside this contract.

Canonical design: [17_LEGACY_DISTRIBUTED_IMPORT.md](../../docs/design/v2/17_LEGACY_DISTRIBUTED_IMPORT.md) and [03_USE_CASES.md](../../docs/design/v2/03_USE_CASES.md) (UC-LGI-001–004).
