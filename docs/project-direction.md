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

## Legacy quarantine

Legacy code may remain for reference, extraction, or migration. New runtime code
must cross legacy boundaries only through explicit import or migration paths.

The following are compatibility inputs under review, not permanent authority:

```text
local.db, history.db, local_favorite.db, implicitData.json
fragmented local databases and mixed app/domain JSON state
legacy IDs and source keys used as runtime identity
direct JavaScript source files without package manifests
hard-coded source tag translation
UI-created reader identity and fallback resume state
```

## Data compatibility

Breaking changes to local data and source-package storage are allowed. Old stores
may be imported on a best-effort basis, but new code must classify every store as
one of:

- canonical authority
- compatibility fallback
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
cookies/               optional authentication/session storage
```

The rule is: a shared database file is acceptable; a shared god-database API is
not.
