# Application Support Layout Authority Policy

Last updated: 2026-05-03

## Goal

Define a stable `Application Support` layout and enforce authority boundaries so runtime/domain authority does not leak back into legacy or implicit stores.

## Target Layout

```text
Application Support/
  data/
    venera.db
    local/
  comic_source/
    *.js
  cookies/
    cookie.db
  config/
    appdata.json
  state/
    window_placement
    implicitData.json
  logs/
    diagnostics.ndjson
```

## Authority Rules

1. `data/venera.db` is canonical domain authority.
2. `data/local/` stores imported local comic blobs/pages/covers only.
3. `appdata.json` is preferences/config state, not domain authority.
4. `implicitData.json` is compatibility/state/cache only, never domain authority.
5. `comic_source/` is source plugin runtime content, not comic-domain authority.
6. `cookies/cookie.db` is auth/session storage only.
7. `logs/diagnostics.ndjson` is diagnostics source of truth, not domain authority.
8. Route/debug decisions must use `logs/diagnostics.ndjson` as evidence authority;
   legacy logs are projection only.

## Current Layout Classification

`appdata.json`
- Class: config/preferences.
- Risk: legacy keys can be treated as authority if read directly without owner classification.

`implicitData.json`
- Class: compatibility bridge + UI/runtime state cache.
- Risk: no schema by default; must never become runtime/domain authority.

`cookie.db`
- Class: session/auth storage.

`comic_source/`
- Class: source plugin files.

`data/`
- Class: canonical storage root for domain DB and local import payloads.

`window_placement`
- Class: UI state.

## Scope for S-layout-1

This slice is documentation and source-boundary only.

- No file migration.
- No data migration.
- No runtime path move.
- Enforce boundary tests for:
  - canonical import path not using `LocalManager`
  - canonical sync path not using `LocalComic.baseDir`
  - `appdata` / `implicitData` keys staying non-domain-authority classifications
