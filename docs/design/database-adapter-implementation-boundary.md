# Database Adapter Implementation Boundary

**Canonical containment rules for future runtime persistence divergence.**

---

## Summary

This document does not commit Venera to shipping PostgreSQL support, server-backed persistence, or adapter abstraction work on a timeline.

It exists to answer one narrower question: if a future approved driver requires a non-SQLite backend or a backend split, where is the allowed insertion seam, and which layers remain no-touch?

Until such a driver exists, SQLite remains the only implementation and speculative indirection stays out of scope.

The future database adapter seam is still a runtime composition concern, not a domain, use-case, or port concern.

---

## Current Seam Inventory

Today, SQLite-specific persistence composition is concentrated in:

- `runtime/core/src/runtime/create-core-runtime.ts`
- `runtime/core/src/db/database.ts`
- `runtime/core/src/repositories/sqlite-repositories.ts`
- `runtime/core/src/db/migrations.ts`
- `runtime/core/src/db/seed.ts`

`runtime/core/src/runtime/create-core-runtime.ts` is the current runtime bootstrap seam. It opens the runtime database, runs migration and seed behavior, assembles repositories, and passes `CoreRepositories` plus `CoreTransactionPort` into the use-case layer.

`runtime/core/src/db/database.ts` is a Node/SQLite infrastructure adapter, not portable shared logic. It owns `better-sqlite3` database opening, Kysely `SqliteDialect` wiring, `PRAGMA foreign_keys = ON`, transaction execution plumbing, and runtime database handle lifecycle.

`runtime/core/src/repositories/sqlite-repositories.ts` is the current SQLite repository implementation surface. Its existence does not prove backend portability of repository SQL.

`runtime/core/src/db/migrations.ts` and `runtime/core/src/db/seed.ts` are part of the live seam because runtime bootstrap invokes them directly.

By contrast, the current use-case dependency boundary remains adapter-agnostic at the type level. `runtime/core/src/ports/use-case-dependencies.ts`, `runtime/core/src/ports/system.ts`, and `runtime/core/src/ports/repositories.ts` expose `CoreRepositories` and `CoreTransactionPort`, not SQLite- or Kysely-specific adapter contracts.

---

## Known SQLite-Specific Surfaces

Current code already contains SQLite-specific or backend-sensitive behavior that must be audited before any non-SQLite work is approved:

- `runtime/core/src/db/database.ts`: `better-sqlite3`, Kysely `SqliteDialect`, and `PRAGMA foreign_keys = ON`
- `runtime/core/src/db/migrations.ts`: `PRAGMA foreign_key_check`
- `runtime/core/src/db/migrations.ts`: partial unique indexes with `WHERE title_kind = 'primary'` and `WHERE is_active = 1`
- `runtime/core/src/db/seed.ts`: `ON CONFLICT(canonical_key) DO UPDATE`

This means "repository ports stay above DB dialects" is a boundary goal, not a proven claim that current SQLite queries, DDL, seed behavior, or migration semantics already transfer unchanged to another backend.

If future audit finds dialect branching or backend-specific query behavior, that branching must stay below `runtime/core/src/ports/**`. If port signatures or use-case contracts need to change, the boundary design must be reopened instead of smuggling backend concerns upward.

---

## Allowed Insertion Boundary

The allowed insertion seam remains runtime composition / persistence assembly.

The first extraction home belongs under `runtime/core/src/runtime/**` because the live composition seam already sits there today.

This is a first-extraction default, not a permanent package-topology commitment. If sibling packages such as `runtime/sqlite` and `runtime/postgres` become justified later, that move must happen in a dedicated topology slice rather than being assumed silently here.

`runtime/core/src/db/**` and `runtime/core/src/repositories/**` remain implementation-side beneath the runtime composition seam.

---

## Composition Authority, Not A God Interface

Runtime bootstrap should own one persistence-composition authority at the seam.

That does not require one mega-interface that mixes every future concern into a single contract.

If a later server-backed backend introduces distinct concerns such as lifecycle, transaction capability, repository assembly, health checks, retries, isolation-level policy, or deadlock handling, those may be split into narrower runtime-only contracts as long as composition ownership stays at the runtime seam and does not leak into `src/domain`, `src/application`, or `src/ports`.

This document constrains the authority location, not the final interface count.

---

## Migration Authority Must Be Explicit Before Backend Split

Migration and seed invocation ownership stays with runtime bootstrap today because `create-core-runtime.ts` directly invokes `migrateCoreDatabase()` and `seedCoreDatabase()`.

That ownership is not "solved later" in the sense of being ignorable. It is a required prerequisite for any real non-SQLite implementation.

No backend-divergent slice may land without an explicit migration-authority sketch that covers:

- who owns backend-specific migration runners
- how versioning is tracked
- where DDL/backend semantic divergence is handled
- how seed orchestration remains runtime-owned or is deliberately moved

The answer may remain bootstrap-owned, or it may move to a dedicated migration authority first. What is not allowed is pretending the adapter seam is settled while migration semantics are still undefined.

---

## Hard Future Guardrails

Any future non-SQLite implementation slice must satisfy all of these constraints:

- `runtime/core/src/domain/**` is unchanged
- `runtime/core/src/application/**` is unchanged
- `runtime/core/src/ports/**` is unchanged
- use-case files stay unchanged

If a PostgreSQL or other backend slice requires edits there, that is evidence the seam is wrong or incomplete, and the work must stop for boundary review.

Repository ports are intended to stay above DB dialects, but current portability is not yet proven. Future implementation work must therefore include an explicit audit of repository SQL, DDL, seed behavior, and transaction semantics rather than assuming a dialect swap is enough.

---

## Required Prerequisites Before Any Backend Split

Before any non-SQLite implementation or abstraction extraction is approved, the repo must have:

- a concrete business or product driver for server-backed persistence, not a hypothetical future
- an audit of known SQLite-specific query, DDL, seed, and migration surfaces
- an explicit migration-authority sketch
- a minimal verification strategy covering fixture lifecycle, isolation, parallelism, and local/CI execution

The full long-term multi-backend test matrix policy can still come later. The minimal verification gate cannot.

---

## Non-Goals

This document does not define:

- PostgreSQL implementation
- connection-pool design
- health-check, retry, or deadlock-recovery policy
- deployment config
- Docker Compose rollout policy
- full long-term backend test matrix policy
- auth/session model changes

---

## Next Slice Handoff

The immediate next slice is not `feat(core): add database adapter abstraction contract`.

The next required slice is a prerequisite audit:

`docs(core): audit SQLite-specific persistence surface and non-SQLite implementation gates`

That follow-up must capture:

- the actual business driver or deployment trigger
- current SQLite-specific repository, migration, and seed surfaces
- the migration-authority evolution path
- the minimal verification strategy
- the hard no-touch diff budget for `runtime/core/src/{domain,application,ports}/**`

Only after that audit is approved should the earliest implementation slice be considered:

`feat(core): extract runtime persistence composition seam`

That later implementation slice should still preserve SQLite as the only implementation and keep the seam confined to runtime composition / persistence assembly.
