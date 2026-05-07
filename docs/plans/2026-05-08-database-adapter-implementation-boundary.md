# Database Adapter Implementation Boundary Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Define the canonical runtime persistence adapter boundary for future PostgreSQL support without changing `runtime/core` domain, application, or port contracts.

**Architecture:** This is a docs-only slice. Create one new canonical design document for adapter implementation boundary, then make minimal authority-doc backlinks so the runtime design index and repository-boundary doc point to the same boundary decision. Use current SQLite runtime composition files as reference inputs only. This slice is self-contained and must not require `docs/design/production-database-adapter-strategy.md` to exist.

**Tech Stack:** Markdown docs, `rg`, `sed`, `git diff --check`

---

## Hard Guards

- This slice is docs-only.
- Do not modify `runtime/core/src/domain/**`, `runtime/core/src/application/**`, or `runtime/core/src/ports/**`.
- Do not modify `runtime/core/src/runtime/create-core-runtime.ts`, `runtime/core/src/db/database.ts`, or `runtime/core/src/repositories/sqlite-repositories.ts`.
- Do not add PostgreSQL code, connection pooling, schema portability code, migration runner policy, Docker Compose, deployment config, or test-matrix implementation.
- Do not create or modify `docs/design/production-database-adapter-strategy.md` in this slice.
- Treat runtime source files as reference inputs only.
- Keep existing canonical docs authoritative; do not route this boundary through legacy design drafts.

## Required Boundary Decisions

### Current seam lives in

```text
runtime/core/src/runtime/create-core-runtime.ts
runtime/core/src/db/database.ts
runtime/core/src/repositories/sqlite-repositories.ts
```

### Future single adapter contract belongs to

```text
runtime composition / persistence assembly
```

### First abstraction contract home belongs to

```text
runtime/core/src/runtime/**
```

### Future single adapter contract must not be inserted into

```text
runtime/core/src/domain/**
runtime/core/src/application/**
runtime/core/src/ports/**
```

### Migration and seed invocation ownership stays with

```text
runtime/core/src/runtime/create-core-runtime.ts
until a later dedicated slice changes that authority explicitly
```

## Required Wording

These exact ideas must appear in the resulting docs:

- The future database adapter seam is a runtime composition concern, not a domain, use-case, or port concern.
- `runtime/core/src/db/database.ts` is a Node/SQLite infrastructure adapter and current seam input, not portable shared logic.
- `runtime/core/src/repositories/sqlite-repositories.ts` is a SQLite-specific repository assembly surface.
- `runtime/core/src/runtime/create-core-runtime.ts` is the current runtime bootstrap seam where SQLite-specific persistence composition is wired.
- A future PostgreSQL implementation must enter through one runtime persistence adapter contract.
- That contract must preserve existing `CoreRepositories` and `CoreTransactionPort` dependency boundaries for use cases.
- The first adapter abstraction contract belongs under `runtime/core/src/runtime/**`, not under `runtime/core/src/ports/**`.
- `runtime/core/src/db/**` and `runtime/core/src/repositories/**` remain implementation-side beneath the runtime composition seam.
- Repository ports stay above DB dialects.
- Migration and seed invocation ownership stays in `runtime/core/src/runtime/create-core-runtime.ts` until a later dedicated slice changes that authority explicitly.
- This slice does not define pooling, migrations, deployment topology, or Docker Compose policy.

## Non-Goals

- no PostgreSQL implementation
- no connection pool
- no migration runner policy
- no schema portability implementation
- no SQLite/PostgreSQL test matrix policy
- no Docker Compose
- no deployment config
- no auth/session model changes

### Task 1: Audit Current Authority and Runtime Seam Surfaces

**Files:**
- Inspect: `docs/design/SUMMARY.md`
- Inspect: `docs/design/repository-interfaces.md`
- Inspect: `runtime/core/src/runtime/create-core-runtime.ts`
- Inspect: `runtime/core/src/db/database.ts`
- Inspect: `runtime/core/src/repositories/sqlite-repositories.ts`
- Inspect: `runtime/core/src/ports/use-case-dependencies.ts`
- Inspect: `runtime/core/src/ports/system.ts`

**Step 1: Capture current seam wording**

Run:

```bash
rg -n "adapter|SQLite|PostgreSQL|createCoreRuntime|openRuntimeDatabase|createCoreRepositories|CoreRepositories|CoreTransactionPort" \
  docs/design runtime/core/src/runtime runtime/core/src/db runtime/core/src/repositories runtime/core/src/ports
```

Expected:
- SQLite-specific runtime composition references are discoverable.
- Use-case dependency ports remain adapter-agnostic.

**Step 2: Confirm doc scope stays narrow**

Record which canonical docs need edits:
- `docs/design/SUMMARY.md`
- `docs/design/repository-interfaces.md`
- new `docs/design/database-adapter-implementation-boundary.md`

Expected:
- No code file becomes a modification target.
- No legacy design draft becomes the authority target.
- No dependency on `docs/design/production-database-adapter-strategy.md` is introduced.

### Task 2: Draft the Canonical Boundary Doc

**Files:**
- Create: `docs/design/database-adapter-implementation-boundary.md`
- Reference only: `runtime/core/src/runtime/create-core-runtime.ts`
- Reference only: `runtime/core/src/db/database.ts`
- Reference only: `runtime/core/src/repositories/sqlite-repositories.ts`
- Reference only: `runtime/core/src/ports/use-case-dependencies.ts`
- Reference only: `runtime/core/src/ports/system.ts`

**Step 1: Write the document skeleton**

Create sections for:
- Summary
- Current seam inventory
- Allowed insertion boundary
- Single adapter contract responsibility
- Forbidden boundary moves
- Required wording
- Non-goals
- Next-slice handoff

**Step 2: Add the strong-constraint seam wording**

The document must explicitly state:
- the current seam lives in `create-core-runtime.ts`, `db/database.ts`, and `sqlite-repositories.ts`
- the future single adapter contract belongs to runtime composition / persistence assembly
- the first abstraction contract belongs under `runtime/core/src/runtime/**`
- the contract must not be inserted into `domain`, `application`, or `ports`
- the current use-case dependency boundary remains `CoreRepositories` + `CoreTransactionPort`
- migration and seed invocation ownership stays in `create-core-runtime.ts` until a later dedicated slice changes it

**Step 3: Add the next-slice handoff**

The document must explicitly state:
- the next slice is `feat(core): add database adapter abstraction contract`
- that slice should extract a composition-layer contract only
- SQLite remains the only implementation in that next slice
- PostgreSQL implementation remains out of scope for that next slice

Expected:
- The new doc becomes the canonical answer for where a future persistence adapter may be inserted.

### Task 3: Update Existing Canonical Docs Minimally

**Files:**
- Modify: `docs/design/SUMMARY.md`
- Modify: `docs/design/repository-interfaces.md`
- Reference only: `docs/design/database-schema.md`

**Step 1: Update the canonical design index**

Add `docs/design/database-adapter-implementation-boundary.md` to `docs/design/SUMMARY.md`.

Expected:
- The new boundary doc appears in the canonical design index.

**Step 2: Add repository-boundary backlink wording**

In `docs/design/repository-interfaces.md`, add a short boundary paragraph clarifying:
- repository ports are not the adapter insertion seam
- SQLite/PostgreSQL adapter composition belongs below ports
- the canonical implementation-boundary authority lives in `docs/design/database-adapter-implementation-boundary.md`

Expected:
- The repository doc says clearly that ports stay above DB dialects and above adapter insertion.
- This slice stays self-contained without touching deployment-strategy authority files.

### Task 4: Verification

**Files:**
- Verify only: `docs/design/database-adapter-implementation-boundary.md`
- Verify only: `docs/design/SUMMARY.md`
- Verify only: `docs/design/repository-interfaces.md`

**Step 1: Check formatting and diff health**

Run:

```bash
git diff --check
```

Expected:
- No trailing whitespace, tab damage, or malformed patch output.

**Step 2: Re-scan wording coverage**

Run:

```bash
rg -n "database adapter|adapter boundary|PostgreSQL adapter|runtime composition|persistence assembly|CoreRepositories|CoreTransactionPort|create-core-runtime|sqlite-repositories" \
  docs/design/database-adapter-implementation-boundary.md \
  docs/design/SUMMARY.md \
  docs/design/repository-interfaces.md
```

Expected:
- The new boundary wording is discoverable in canonical docs.
- Verification does not rely on matches inside `docs/plans/**`.
- This slice does not depend on `docs/design/production-database-adapter-strategy.md` existing.
