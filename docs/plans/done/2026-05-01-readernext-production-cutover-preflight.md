# ReaderNext Production Cutover Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire `reader_next` into production app entrypoints with strict fail-closed identity boundaries and no legacy runtime contamination.

**Architecture:** Keep runtime kernel unchanged and introduce a one-way bridge layer that converts existing app models into `ReaderNextOpenRequest`. All production opens must pass typed identity (`CanonicalComicId` + valid `SourceRef` for remote). UI controllers accept only bridge output and render typed boundary failure, never legacy fallback.

**Tech Stack:** Flutter, Dart, `flutter_test`, existing ReaderNext runtime types under `lib/features/reader_next/runtime/*`.

---

### Task 1: Remote Open Boundary Guard Tests First

**Files:**
- Modify: `test/features/reader_next/runtime/boundary_validation_test.dart`
- Test: `test/features/reader_next/runtime/boundary_validation_test.dart`

**Step 1: Write the failing tests**

```dart
test('remote ReaderNext open request requires SourceRef', () {
  final sourceRef = SourceRef.remote(
    sourceKey: 'nhentai',
    upstreamComicRefId: '646922',
    chapterRefId: '0',
  );
  final request = ReaderNextOpenRequest.remote(
    canonicalComicId: CanonicalComicId.remote(
      sourceKey: 'nhentai',
      upstreamComicRefId: '646922',
    ),
    sourceRef: sourceRef,
    initialPage: 1,
  );
  expect(request.sourceRef, sourceRef);
});

test('bridge rejects canonical id as upstreamComicRefId', () {
  expect(
    () => SourceRef.remote(
      sourceKey: 'nhentai',
      upstreamComicRefId: 'remote:nhentai:646922',
      chapterRefId: '0',
    ),
    throwsA(isA<ReaderNextBoundaryException>()),
  );
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/features/reader_next/runtime/boundary_validation_test.dart`
Expected: FAIL for missing/null `SourceRef` or canonical-in-upstream rejection path not enforced.

**Step 3: Write minimal implementation**

```dart
// In runtime boundary constructors/validators, enforce:
// - remote open requires non-null SourceRef
// - SourceRef.upstreamComicRefId must reject canonical-prefixed values
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/features/reader_next/runtime/boundary_validation_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add test/features/reader_next/runtime/boundary_validation_test.dart lib/features/reader_next/runtime/models.dart
git commit -m "test(reader_next): enforce remote open sourceRef boundary guards"
```

### Task 2: Add One-Way Bridge Contract

**Files:**
- Create: `lib/features/reader_next/bridge/reader_next_open_bridge.dart`
- Create: `test/features/reader_next/bridge/reader_next_open_bridge_test.dart`
- Test: `test/features/reader_next/bridge/reader_next_open_bridge_test.dart`

**Step 1: Write the failing tests**

```dart
test('bridge maps remote comic models to ReaderNextOpenRequest with SourceRef', () {
  // Arrange app model fixture
  // Act bridge.toOpenRequest(...)
  // Assert remote request contains canonical + valid SourceRef
});

test('bridge fails closed on missing/malformed SourceRef fields', () {
  expect(
    () => bridge.toOpenRequest(invalidFixture),
    throwsA(isA<ReaderNextBoundaryException>()),
  );
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/features/reader_next/bridge/reader_next_open_bridge_test.dart`
Expected: FAIL because bridge file/function does not exist yet.

**Step 3: Write minimal implementation**

```dart
class ReaderNextOpenBridge {
  ReaderNextOpenRequest toOpenRequest({required ExistingComicModel comic}) {
    // one-way adapter only, no runtime kernel imports from legacy reader
    // validate sourceKey/upstreamComicRefId/chapterRefId before building SourceRef
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/features/reader_next/bridge/reader_next_open_bridge_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/features/reader_next/bridge/reader_next_open_bridge.dart test/features/reader_next/bridge/reader_next_open_bridge_test.dart
git commit -m "feat(reader_next): add one-way open-request bridge with fail-closed validation"
```

### Task 3: Restrict Presentation Controller Input Surface

**Files:**
- Modify: `lib/features/reader_next/presentation/open_reader_controller.dart`
- Modify: `test/features/reader_next/presentation/open_reader_controller_test.dart`
- Test: `test/features/reader_next/presentation/open_reader_controller_test.dart`

**Step 1: Write the failing tests**

```dart
test('controller accepts only ReaderNextOpenRequest', () {
  // compile-time + runtime test helpers ensure no raw comic.id route
});

test('controller renders typed fail-closed UI on boundary exception', () async {
  // simulate bridge boundary error and assert fail-closed state
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/features/reader_next/presentation/open_reader_controller_test.dart`
Expected: FAIL due to existing mixed/raw route input surface.

**Step 3: Write minimal implementation**

```dart
class OpenReaderController {
  Future<void> open(ReaderNextOpenRequest request) async {
    // no raw id parameters
    // no legacy fallback route
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/features/reader_next/presentation/open_reader_controller_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/features/reader_next/presentation/open_reader_controller.dart test/features/reader_next/presentation/open_reader_controller_test.dart
git commit -m "refactor(reader_next): limit controller input to typed open request"
```

### Task 4: Add Authority Guard + Redacted Cutover Logging

**Files:**
- Modify: `test/features/reader_next/runtime/authority_imports_test.dart`
- Modify: `lib/features/reader_next/presentation/open_reader_controller.dart`
- Modify: `test/features/reader_next/presentation/open_reader_controller_test.dart`
- Test: `test/features/reader_next/runtime/authority_imports_test.dart`
- Test: `test/features/reader_next/presentation/open_reader_controller_test.dart`

**Step 1: Write the failing tests**

```dart
test('ReaderNext presentation/runtime does not import old reader files', () {
  // authority scan denies legacy reader imports
});

test('production open path emits redacted identity fields', () async {
  // assert log payload includes sourceRef/canonical/upstream fields redacted
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/features/reader_next/runtime/authority_imports_test.dart`
Run: `flutter test test/features/reader_next/presentation/open_reader_controller_test.dart`
Expected: FAIL if import guard and structured redacted logs are not implemented.

**Step 3: Write minimal implementation**

```dart
// authority test: deny old reader/runtime manager imports
// controller logging: emit redacted map, never raw ids/tokens
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/features/reader_next/runtime/authority_imports_test.dart`
Run: `flutter test test/features/reader_next/presentation/open_reader_controller_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add test/features/reader_next/runtime/authority_imports_test.dart lib/features/reader_next/presentation/open_reader_controller.dart test/features/reader_next/presentation/open_reader_controller_test.dart
git commit -m "test(reader_next): enforce cutover import guard and redacted production open logs"
```

### Task 5: Full M10 Verification Gate

**Files:**
- Modify: `docs/plans/agent-shared.md`
- Test: `test/features/reader_next/bridge/*`
- Test: `test/features/reader_next/presentation/*`
- Test: `test/features/reader_next/runtime/authority_*`

**Step 1: Write failing gate checklist (if missing)**

```markdown
- [ ] remote open requires non-null typed SourceRef
- [ ] canonical id rejected as upstreamComicRefId
- [ ] no legacy reader imports in ReaderNext paths
- [ ] production route logs redacted identity fields
```

**Step 2: Run focused verification suite**

Run: `flutter test test/features/reader_next/bridge`
Run: `flutter test test/features/reader_next/presentation`
Run: `flutter test test/features/reader_next/runtime/authority_*`
Expected: PASS all

**Step 3: Run static hygiene checks**

Run: `dart analyze lib/features/reader_next`
Run: `git diff --check`
Expected: no analyzer issues; no whitespace/conflict issues.

**Step 4: Mark M10 tasks status**

```markdown
Update M10-T1..M10-T4 in docs/plans/agent-shared.md from todo -> done only after all checks pass.
```

**Step 5: Commit**

```bash
git add docs/plans/agent-shared.md
git commit -m "docs(plan): complete M10 cutover verification gate"
```

## Skill References

- `@superpowers:executing-plans` for implementation handoff.
- `@superpowers:verification-before-completion` before claiming lane completion.
- `@superpowers:requesting-code-review` after M10 verification gate passes.
