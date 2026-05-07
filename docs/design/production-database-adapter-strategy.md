# Production Database Adapter Strategy

**Canonical deployment-mode and database-adapter boundary for V1 runtime persistence.**

---

## Summary

V1 runtime schema, repository ports, and use cases are dialect-portable authority. SQLite remains a valid adapter for local, embedded, test, and temporary demo workflows. PostgreSQL is the preferred production target for self-hosted web deployment, multi-device access, long-running server operation, and future multi-user hosting.

This document defines which deployment modes may use SQLite, which deployment modes should target PostgreSQL, and which boundaries must stay stable before any production PostgreSQL implementation begins.

---

## Current Runtime Status

Today, `runtime/core/src/db/database.ts` opens a `better-sqlite3` database through Kysely's `SqliteDialect`. That file is a Node/SQLite infrastructure adapter, not portable shared logic.

Current `apps/web` shell creates the runtime with `databasePath: ":memory:"`, reports `mode: "demo-memory"` with `persisted: false`, and is intentionally non-persistent.

Production web persistence must not be represented as `:memory:` or demo SQLite.

---

## Deployment-Mode Split

| Mode                                | Preferred persistence target                  | Notes                                                           |
| ----------------------------------- | --------------------------------------------- | --------------------------------------------------------------- |
| Dev smoke                           | SQLite                                        | Ephemeral or local-only runtime is valid.                       |
| Tests                               | SQLite                                        | Fast embedded test persistence is valid.                        |
| Desktop-local mode                  | SQLite                                        | Single-user embedded runtime is valid.                          |
| Single-user embedded mode           | SQLite                                        | Local shell-owned persistence is valid.                         |
| Android local embedded mode         | SQLite                                        | Embedded mobile shell storage is valid.                         |
| Native iOS/iPadOS shell experiments | SQLite only if a real local DB adapter exists | Future native-shell experiment only; not a browser/PWA promise. |
| Temporary demo runtime              | SQLite or `:memory:`                          | Demo-only and intentionally non-persistent.                     |
| Self-hosted web mode                | PostgreSQL                                    | Preferred production target.                                    |
| Multi-device access                 | PostgreSQL                                    | Server-backed persistence is preferred.                         |
| Long-running server deployment      | PostgreSQL                                    | Production persistence target.                                  |
| Future multi-user deployment        | PostgreSQL                                    | Preferred production target.                                    |

iOS/iPadOS browser/PWA mode remains thin-client only. Embedded database support is only a future native-shell experiment.

---

## SQLite-Valid Modes

SQLite remains valid for:

- dev smoke
- tests
- desktop-local mode
- single-user embedded mode
- Android local embedded mode
- native iOS/iPadOS shell experiments, if a real local DB adapter exists
- temporary demo runtime

These SQLite-valid modes do not authorize production web persistence, long-running multi-device persistence, or future shared-server deployment to remain on demo SQLite.

---

## PostgreSQL-Preferred Modes

PostgreSQL is the preferred production target for:

- self-hosted web mode
- multi-device access
- long-running server deployment
- future multi-user deployment

Any future PostgreSQL adapter must implement the same repository/use-case contracts without changing domain or application code.

PostgreSQL support must be added as an adapter/runtime infrastructure slice, not as a domain-model rewrite.

---

## Boundary Rules

- `runtime/core` use cases stay DB-dialect independent.
- Repository ports stay above DB dialects.
- DB adapters are infrastructure.
- DB adapters are not portable shared logic.
- Web client never talks to DB directly.
- Source packages never talk to DB directly.
- Docker Compose belongs to deployment layer, not core logic.

`runtime/core/src/db/database.ts` is a Node/SQLite infrastructure adapter, not portable shared logic.

Any future PostgreSQL adapter must satisfy the existing repository and use-case contracts without moving dialect-specific concerns into `src/domain`, `src/application`, or `src/ports`.

---

## Contract Statements

- `runtime/core/src/db/database.ts` is a Node/SQLite infrastructure adapter, not portable shared logic.
- Any future PostgreSQL adapter must implement the same repository/use-case contracts without changing domain or application code.
- Production web persistence must not be represented as `:memory:` or demo SQLite.
- Current `apps/web` shell is `demo-memory` only and intentionally non-persistent.
- iOS/iPadOS browser/PWA mode remains thin-client only.
- Embedded iOS/iPadOS database support is only a future native-shell experiment.

---

## Non-Goals

- no PostgreSQL implementation
- no schema migration runner
- no Docker Compose
- no connection pooling
- no deployment config
- no auth/session model
- no package store implementation
