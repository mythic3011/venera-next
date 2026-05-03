# F-favorite-authority-inventory-1

Date: 2026-05-04  
Scope: Inventory only. No runtime/storage authority change.

## Goal

Document current legacy favorite runtime authority usage so follow-up migration can be explicit and bounded.

## Current Authority State

- Local favorite panel/runtime actions in `comic_details_page` still use legacy bridge APIs.
- Canonical-first import/runtime routing work exists in other areas, but this favorite panel path remains legacy-backed.
- This document marks the mismatch intentionally to prevent accidental partial migration.

## Legacy Callsite Inventory

### Authority wrapper definitions

- `lib/foundation/comic_detail_legacy_bridge.dart:22` `legacyLocalFavoriteFolderNames()`
- `lib/foundation/comic_detail_legacy_bridge.dart:26` `legacyLocalFavoriteMembership(String comicId, ComicType type)`
- `lib/foundation/comic_detail_legacy_bridge.dart:30` `legacyLocalFavoriteExists(String comicId, ComicType type)`
- `lib/foundation/comic_detail_legacy_bridge.dart:34` `legacyAddLocalFavorite(...)`
- `lib/foundation/comic_detail_legacy_bridge.dart:42` `legacyDeleteLocalFavorite(...)`

### Runtime UI usage (favorite panel / detail actions)

- `lib/pages/comic_details_page/favorite.dart:45` `legacyLocalFavoriteFolderNames()`
- `lib/pages/comic_details_page/favorite.dart:46` `legacyLocalFavoriteMembership(widget.cid, widget.type)`
- `lib/pages/comic_details_page/favorite.dart:548` `legacyDeleteLocalFavorite(folder, widget.cid, widget.type)`
- `lib/pages/comic_details_page/favorite.dart:554` `legacyAddLocalFavorite(folder, widget.favoriteItem, widget.updateTime)`
- `lib/pages/comic_details_page/favorite.dart:587` `legacyLocalFavoriteFolderNames()` (refresh after new folder)
- `lib/pages/comic_details_page/actions.dart:172` `legacyAddLocalFavorite(folder, _toFavoriteItem(), comic.findUpdateTime())`

## Boundary For Next Migration Slice

### In scope for future migration slice

- Replace `legacyLocalFavorite*` runtime UI calls with one explicit canonical favorite authority surface.
- Keep behavior parity for:
  - folder list/read
  - membership read
  - add/remove favorite
  - new folder refresh

### Out of scope for this inventory slice

- No storage format migration.
- No fallback strategy changes.
- No UI behavior or UX changes.

## Suggested Next Slice Contract

`F-favorite-authority-migration-1`:

1. Introduce a single runtime authority entrypoint for local favorites (non-legacy-named surface).
2. Rewire `comic_details_page/favorite.dart` and `actions.dart` to that entrypoint.
3. Add regression checks for folder membership/add/remove parity.
4. Keep import path and settings behavior unchanged in this slice.
