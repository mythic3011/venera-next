# Database Adapter Implementation Boundary Design

**Status:** Approved design for the next runtime/core docs-only slice
**Date:** May 8, 2026

---

## Goal

Define the canonical implementation boundary for a future runtime persistence adapter so PostgreSQL support can be added later without changing `runtime/core` domain, use-case, or port contracts.

This design answers one question only: where the future database adapter seam belongs, and which layers are explicitly not allowed to move because of adapter concerns.

---

## Current State

Today, SQLite-specific composition is concentrated in three files:

- `runtime/core/src/runtime/create-core-runtime.ts`
- `runtime/core/src/db/database.ts`
- `runtime/core/src/repositories/sqlite-repositories.ts`

`create-core-runtime.ts` currently hard-wires runtime persistence bootstrap by:

- opening the runtime database through `openRuntimeDatabase()`
- running migration/seed behavior against that handle
- assembling repositories through `createCoreRepositories()`
- passing `CoreRepositories` and `CoreTransactionPort` into use cases

`db/database.ts` is a Node/SQLite infrastructure adapter that owns:

- `better-sqlite3` database opening
- Kysely `SqliteDialect` wiring
- transaction execution plumbing through `QueryExecutorProvider`
- runtime database handle lifecycle

`sqlite-repositories.ts` is the SQLite-specific repository assembly surface.

By contrast, the current use-case dependency boundary is already adapter-agnostic:

- `runtime/core/src/ports/use-case-dependencies.ts`
- `runtime/core/src/ports/system.ts`
- `runtime/core/src/ports/repositories.ts`

Those files expose `CoreRepositories` and `CoreTransactionPort`, not SQLite or Kysely-specific adapter contracts.

---

## Decision

Future PostgreSQL support must be introduced through one runtime persistence adapter contract.

That adapter contract belongs to `runtime composition / persistence assembly`, not to:

- `runtime/core/src/domain/**`
- `runtime/core/src/application/**`
- `runtime/core/src/ports/**`

The adapter seam must be extracted from the current runtime bootstrap path, not by widening port contracts and not by pushing database lifecycle concerns into use cases.

---

## Recommended Approach

### Recommended

Use a **runtime composition adapter** approach.

The single adapter contract should sit at the runtime bootstrap boundary and should be responsible for:

- opening and closing persistence runtime resources
- exposing transaction capability needed by use cases
- assembling repository implementations for the selected backing store
- returning the persistence dependencies needed to build `CoreRuntime`

The first abstraction contract should live under `runtime/core/src/runtime/**` as a composition-layer contract. `runtime/core/src/db/**` and `runtime/core/src/repositories/**` remain implementation-side beneath that runtime composition seam.

This keeps adapter concerns in infrastructure/runtime assembly, which is where the current SQLite-specific seam already lives.

### Rejected

Do not introduce a ports-level adapter.

If adapter lifecycle, dialect, or pooling concerns are pushed into `runtime/core/src/ports/**`, the application contract becomes infrastructure-aware and the current clean use-case dependency boundary is weakened.

Do not introduce a repository-factory-only seam.

Only abstracting repository creation is too narrow, because future PostgreSQL work will also need lifecycle, transaction integration, and runtime bootstrap ownership. A partial seam would leave SQLite-specific infrastructure split across multiple unrelated files.

---

## Strong Constraints

The future adapter seam may only be extracted from these current ownership points:

- `runtime/core/src/runtime/create-core-runtime.ts`
- `runtime/core/src/db/database.ts`
- `runtime/core/src/repositories/sqlite-repositories.ts`

The following contract surfaces must not change shape because of adapter work:

- `runtime/core/src/domain/**`
- `runtime/core/src/application/**`
- `runtime/core/src/ports/**`

The docs slice must state clearly that:

- the adapter contract is a runtime composition concern
- SQLite and future PostgreSQL are infrastructure implementations under one adapter authority
- repository ports remain above DB dialects
- use cases continue to depend only on `CoreRepositories` and `CoreTransactionPort`
- the first contract home belongs under `runtime/core/src/runtime/**`, not under `src/ports/**`
- migration and seed invocation ownership stays with runtime bootstrap until a later dedicated slice changes that authority explicitly

---

## Non-Goals

This slice does not define or implement:

- PostgreSQL dialect code
- connection pooling
- schema portability mechanics
- migration runner policy
- SQLite/PostgreSQL test matrix policy
- Docker Compose deployment
- auth/session changes
- package store changes

Those are follow-up implementation or deployment slices, not part of the authority decision here.

---

## Canonical Doc Impact

The approved docs-only slice should:

- create `docs/design/database-adapter-implementation-boundary.md`
- add it to `docs/design/SUMMARY.md`
- add a minimal ports-boundary backlink in `docs/design/repository-interfaces.md`

This slice is self-contained and must not require `docs/design/production-database-adapter-strategy.md` to exist. If that deployment-strategy authority is added or landed later, any backlink to this boundary document belongs in a separate docs-only slice.

---

## Acceptance Criteria

The resulting authority docs must make these answers explicit:

- Where does the future database adapter seam belong?
- Which module family is the allowed home for the first adapter abstraction contract?
- Which existing files define the current SQLite-specific seam?
- Which layers are forbidden from changing because of adapter concerns?
- Why is the seam a runtime composition concern rather than a ports concern?
- Who keeps migration and seed invocation ownership until a later dedicated slice says otherwise?
- What is the exact next implementation slice after this docs-only authority pass?

---

## Next Slice Handoff

The next implementation slice after this design is:

`feat(core): add database adapter abstraction contract`

That next slice should stay minimal:

- define the single adapter abstraction/contract
- preserve SQLite as the only implementation
- keep abstraction extraction confined to runtime composition / persistence assembly
- place the first contract under `runtime/core/src/runtime/**`
- leave migration and seed invocation ownership in `create-core-runtime.ts` until a later dedicated slice changes it
- add tests around the new composition contract

It must not add PostgreSQL implementation in the same cut.
