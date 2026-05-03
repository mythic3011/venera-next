# RootContext Inventory

Date: 2026-05-04  
Scope: full-repo inventory and classification only; no runtime behavior change.

## Goal

- Inventory all `App.rootContext` usage.
- Classify each usage surface as allowed vs should-refactor.
- Define first migration rules and a guard so future additions are explicit.

## Classification Model

- `allowed_bootstrap`: main/app init only.
- `allowed_emergency`: top-level crash/error fallback only.
- `ui_navigation`: should migrate to local `BuildContext`, `AppRouter`, or typed navigation service.
- `ui_message`: should migrate to caller-owned context; if source is background/service, return typed result instead.
- `dialog_popup`: should migrate to widget-owned context and guard `context.mounted` after async gap.
- `background_service`: must not show UI directly; emit `AppDiagnostics` + typed result/event.
- `unknown`: owner pending.

## Guardrails

Guardrail 1:
- This inventory does not approve existing `App.rootContext` usages.
- It records current legacy upstream architecture debt and forces new usages to be classified.

Guardrail 2:
- Any newly added `App.rootContext` usage must be either `allowed_bootstrap` or `allowed_emergency`,
  or it must include a migration note and owner.

## Inventory Results (Global Context Series)

Scope pattern:
- `App.rootContext`
- `App.rootNavigatorKey.currentContext`
- `App.mainNavigatorKey?.currentContext`

Total files with global-context access: **16**

### allowed_bootstrap

- `lib/main.dart`

### allowed_emergency

- None currently classified.

### ui_navigation

- `lib/app/navigation/app_links.dart`
- `lib/app/navigation/handle_text_share.dart`
- `lib/components/comic.dart`
- `lib/pages/comic_source_page.dart`
- `lib/pages/favorites/local_favorites_page.dart`
- `lib/pages/image_favorites_page/image_favorites_item.dart`
- `lib/pages/local_comics_page.dart`

### ui_message

- None currently classified.

### dialog_popup

- `lib/components/js_ui.dart`
- `lib/components/message.dart`

### background_service

- `lib/foundation/local/local_comic.dart`
- `lib/init.dart`
- `lib/network/cloudflare.dart`
- `lib/utils/data_sync.dart`
- `lib/utils/import_comic.dart`
- `lib/utils/io.dart`

### unknown

- None currently classified.

## First Refactor Rules (Batch 1)

- Reader open path: `AppRouter.openReader` only.
- Settings/about/check-update dialogs: pass `BuildContext` into UI entry (`checkUpdateUi(context, ...)`) and guard with `if (!context.mounted) return;` after `await`.
- Snackbar/message: caller-owned context only; no `App.rootContext` in normal UI flows.
- Background/network code: no direct UI call; return typed result + `AppDiagnostics` event.

## Demo Slice Target

`U-rootcontext-about-1`:

- `checkUpdateUi(BuildContext context, ...)`
- `onPressed` async/await
- `if (!mounted) return;` before `setState`
- `if (!context.mounted) return;` before `showDialog`/`showMessage`
- `AppDiagnostics.error('settings.about', 'settings.about.checkUpdate.failed', ...)`
- no behavior change

## Guardrail Test

- `test/architecture/root_context_inventory_test.dart` enforces that every file using the global-context series patterns is explicitly classified.
- For non-allowed categories, the test also requires owner + migration note metadata.
