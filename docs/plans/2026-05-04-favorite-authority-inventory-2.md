# F-favorite-authority-inventory-2

Date: 2026-05-04  
Scope: Favorite-related legacy authority stratification only (no runtime behavior changes).

## Goal

Expand inventory beyond `favorite.dart` and define phased migration boundaries for favorite-related legacy runtime authority.

## Layered Inventory

### Layer 1: Favorite Panel + Detail Actions (shortest first)

Primary risk: UI/domain mutation paths still call legacy favorite authority wrappers directly.

- `lib/pages/comic_details_page/favorite.dart`
  - `legacyLocalFavoriteFolderNames()` read
  - `legacyLocalFavoriteMembership(...)` read
  - `legacyAddLocalFavorite(...)` write
  - `legacyDeleteLocalFavorite(...)` write
- `lib/pages/comic_details_page/actions.dart:172`
  - `legacyAddLocalFavorite(...)` write
- `lib/foundation/comic_detail_legacy_bridge.dart`
  - `legacyLocalFavorite*` wrapper surface over `LocalFavoritesManager()`

Migration intent:

- Replace page-level `legacyLocalFavorite*` calls with one explicit favorite runtime authority entrypoint.
- Preserve exact current UX and side effects.

Out of scope:

- storage schema changes
- route/reader cutover changes

### Layer 2: Follow Updates Favorite Coupling

Primary risk: follow-updates flows directly own favorite manager state transitions.

- `lib/pages/follow_updates_page.dart`
  - multiple direct `LocalFavoritesManager()` reads/writes/inits
- `lib/foundation/follow_updates.dart`
  - update/check/notify flows directly invoke `LocalFavoritesManager()`
- `lib/pages/home_page_legacy_sections.dart:4`
  - direct folder list read from `LocalFavoritesManager().folderNames`

Migration intent:

- Move follow-updates favorite access behind explicit favorite authority/repository boundary.
- Keep follow-updates behavior parity (counts, read markers, update time, check time).

Out of scope:

- redesign of follow-updates UX
- replacing non-favorite local-library authority in same slice

### Layer 3: History Coupling to Favorite Existence

Primary risk: history cleanup logic depends on favorite existence via legacy manager call.

- `lib/foundation/history.dart:376`
  - `LocalFavoritesManager().isExist(id, type)` in `clearUnfavoritedHistory()`

Migration intent:

- Replace history-to-favorite coupling with authority-owned query API.
- Keep cleanup semantics unchanged.

Out of scope:

- history storage model rewrite
- reader session semantics changes

## Canonical Boundaries (for next implementation slices)

1. A single favorite runtime authority surface should own:
   - folder list/read
   - membership lookup
   - add/remove operations
   - follow-updates-required favorite metadata queries
2. UI pages should call authority APIs, not `LocalFavoritesManager` or `legacyLocalFavorite*`.
3. Compatibility helpers may remain temporarily, but must be bridge-only and non-authoritative.

## Suggested Execution Order

1. `F-favorite-authority-migration-1` (Layer 1 only)
2. `F-favorite-authority-migration-2` (Layer 2 only)
3. `F-favorite-authority-migration-3` (Layer 3 only)

Each slice constraints:

- no UX changes
- no storage migration
- add parity-focused regression coverage for touched layer only
