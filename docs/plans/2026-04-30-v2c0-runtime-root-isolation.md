# V2C0 Runtime Root Isolation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Isolate macOS debug/dev runtime data roots so migration slices can be verified without reusing the long-lived `com.mythic3011.veneranext` app-support directory.

**Architecture:** Keep production bundle/runtime paths unchanged. Add an explicit dev-only runtime-root override path that is resolved before `App.init()` opens `data/venera.db`, `local.db`, `local_favorite.db`, or `history.db`. Diagnostics must surface the active runtime root so migration verification can prove which data namespace is in use.

**Tech Stack:** Flutter, macOS bundle config, `path_provider`, existing `App` bootstrap, diagnostics service.

---

This slice must isolate debug/dev runtime state before authority migration begins. It must not change production persistence paths.

### Task 1: Add runtime root override plumbing

**Files:**
- Modify: `lib/foundation/app.dart`
- Modify: `lib/foundation/debug_diagnostics_service.dart`
- Test: `test/foundation/app_boot_authority_test.dart`

**Steps:**
1. Add a single runtime-root resolver in `App` that prefers an explicit dev override before `getApplicationSupportDirectory()`.
2. Make `App.init()` derive `dataPath` / `cachePath` from that resolver before opening any database.
3. Extend diagnostics output to include the resolved runtime root and whether override mode is active.
4. Add/extend a bootstrap test proving the override path becomes the authority root for both canonical and legacy runtime files.
5. Run the focused tests and commit.

### Task 2: Add macOS dev-only entrypoint/config

**Files:**
- Modify: `macos/Runner/Configs/AppInfo.xcconfig`
- Modify: `macos/Runner/Info.plist`
- Modify: `scripts/build-macos-dmg.sh`
- Test: `test/foundation/app_boot_authority_test.dart`

**Steps:**
1. Add a debug/dev-only switch that opts into an isolated runtime root without changing release bundle behavior.
2. Document the switch in the macOS build script output/help so dev builds can intentionally use clean state.
3. Keep production bundle id and production runtime paths unchanged.
4. Verify a normal release-style boot still resolves the existing root while override mode resolves the isolated root.
5. Run focused verification and commit.

### Task 3: Add operator-facing verification hooks

**Files:**
- Modify: `lib/pages/settings/debug.dart`
- Modify: `lib/foundation/debug_diagnostics_service.dart`
- Test: `test/foundation/debug_log_exporter_test.dart`

**Steps:**
1. Expose the resolved runtime root in the debug UI and diagnostics payload.
2. Ensure exported diagnostics/log snapshots include the runtime-root field.
3. Add a focused test proving the field is present when diagnostics export runs.
4. Run focused verification and commit.

### Acceptance

```bash
flutter test test/foundation/app_boot_authority_test.dart test/foundation/debug_log_exporter_test.dart
flutter analyze
```

### Notes

- Do not change production app data semantics in this slice.
- Do not move legacy databases yet.
- This slice must land before V2C-V2F so runtime-state verification is trustworthy.
