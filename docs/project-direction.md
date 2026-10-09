# Project direction and compatibility

## Fork status

`venera-next` is not a conservative maintenance fork. The upstream repository
is archived/read-only and is treated as a legacy reference and extraction source,
not as the architecture authority for new runtime work.

The fork is maintained by `mythic3011` on a best-effort, personal-use-first
basis. It is not a guaranteed support service.

The intended ownership boundaries are:

- UI expresses user intent.
- Application/use-case services coordinate flows.
- Domain models own identity and rules.
- Repositories access canonical storage.
- Database code owns schema, migrations, and transactions.
- Runtime code owns reader and source execution.
- Diagnostics report evidence; they do not repair invalid state.
- Legacy code does not own live runtime authority.

## Greenfield v2 implementation ruling (2026-10-09)

The current legacy/runtime code is **discarded as an implementation base**. Venera Next v2 is built afresh from `docs/design/v2/` canonical domain, storage, reader, plugin and security contracts. Do not adapt old `Comic/Chapter/Page` models or existing `runtime/core` migration code as a compatibility foundation.

- **No legacy runtime dependency or in-place schema migration** is required. New v2 database tables are created directly with `Content/ContentSection/ContentUnit` identifiers and complete invariants.
- No promise of binary compatibility, legacy direct-JS plugin compatibility, account cookie/session reuse or preserved legacy APIs. Any past code may only inform human review or independently written tests.
- **One-time old-Venera import uses a strict five-file whitelist**: `local.db`, `history.db`, `local_favorite.db`, `appdata.json`, `implicitData.json`. Legacy Unified Store `venera.db` and all other old DB/JSON inputs are explicitly excluded. The imported data goes through independent read-only snapshots, explicit review and fresh v2 canonical writers; see proposed `docs/design/v2/17_LEGACY_DISTRIBUTED_IMPORT.md`.
- This policy itself does **not** delete files or user data. Physical removal of old source trees belongs to a separate reviewed implementation PR.

## Legacy quarantine

Legacy code may remain temporarily as archived reference only. New runtime code
must not import, execute or depend on it. An optional one-way data importer is
an independent ingestion tool, not a cross-runtime bridge.

The following are compatibility inputs under review, not permanent authority:

```text
local.db, history.db, local_favorite.db, appdata.json, implicitData.json
# Exactly these five distributed legacy files; Unified Store venera.db is excluded.
legacy IDs and source keys used as runtime identity
direct JavaScript source files without package manifests
hard-coded source tag translation
UI-created reader identity and fallback resume state
```

## Data compatibility

Breaking changes to local data and source-package storage are allowed. Only the five named distributed legacy files may be imported, by explicit user action; Unified Store venera.db is not accepted. New code classifies eligible input as
one of:

- canonical authority
- one-way data import input (optional, never live runtime fallback)
- cache
- preference/configuration
- diagnostic-only state

The target storage shape is:

```text
data/venera.db         canonical domain database
blobs/                 covers, pages, imports, and cache files
plugins/               verified source-package artifacts
source_repositories/   repository indexes and package metadata cache
taxonomy/              canonical tags, labels, and provider mappings
logs/                  diagnostics and exported logs
config/                application preferences
vault/                 optional encrypted credential records only; keys in OS/vault backend
```

The rule is: a shared database file is acceptable; a shared god-database API is
not.
