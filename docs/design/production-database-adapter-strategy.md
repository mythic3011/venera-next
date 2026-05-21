# Production Database Adapter Strategy

**Canonical deployment-mode and database-adapter boundary for V1 runtime persistence.**

---

## Summary

This document is conditional deployment-direction guidance, not a commitment to ship PostgreSQL support or adapter abstraction work on a dated roadmap.

V1 runtime schema, repository ports, and use cases remain the authority boundary. SQLite remains a valid adapter for local, embedded, test, and temporary demo workflows. If product scope later commits to self-hosted web deployment, multi-device access, long-running server operation, or future multi-user hosting, those modes require an explicit server-backed persistence decision. PostgreSQL is a current candidate direction for that decision, not an approved roadmap promise.

This document defines which deployment modes may use SQLite, which deployment modes would require a server-backed persistence decision if they become committed scope, and which boundaries must stay stable before any production backend split begins.

---

## Current Runtime Status

Today, `runtime/core/src/db/database.ts` opens a `better-sqlite3` database through Kysely's `SqliteDialect`. That file is a Node/SQLite infrastructure adapter, not portable shared logic.

Current `apps/web` shell creates the runtime with `databasePath: ":memory:"`, reports `mode: "demo-memory"` with `persisted: false`, and is intentionally non-persistent.

Production web persistence must not be represented as `:memory:` or demo SQLite.

---

## Deployment-Mode Split

| Mode                                | Current persistence position                             | Notes                                                                    |
| ----------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------ |
| Dev smoke                           | SQLite                                                   | Ephemeral or local-only runtime is valid.                                |
| Tests                               | SQLite                                                   | Fast embedded test persistence is valid.                                 |
| Desktop-local mode                  | SQLite                                                   | Single-user embedded runtime is valid.                                   |
| Single-user embedded mode           | SQLite                                                   | Local shell-owned persistence is valid.                                  |
| Android local embedded mode         | SQLite                                                   | Embedded mobile shell storage is valid.                                  |
| Native iOS/iPadOS shell experiments | SQLite only if a real local DB adapter exists            | Future native-shell experiment only; not a browser/PWA promise.          |
| Temporary demo runtime              | SQLite or `:memory:`                                     | Demo-only and intentionally non-persistent.                              |
| Self-hosted web mode                | Server-backed adapter required if this mode is approved  | PostgreSQL is a current candidate, not a committed roadmap.              |
| Multi-device access                 | Server-backed adapter required if this mode is approved  | PostgreSQL is a current candidate, not a committed roadmap.              |
| Long-running server deployment      | Server-backed adapter required if this mode is approved  | PostgreSQL is a current candidate, not a committed roadmap.              |
| Future multi-user deployment        | Server-backed adapter required if this mode is approved  | PostgreSQL is a current candidate, not a committed roadmap.              |

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

## Server-Backed Candidate Modes

If these deployment modes become committed product scope, they require an explicit server-backed persistence decision. PostgreSQL is a current candidate direction for:

- self-hosted web mode
- multi-device access
- long-running server deployment
- future multi-user deployment

Any future PostgreSQL adapter work is expected to preserve the same repository/use-case contracts without changing domain or application code. That expectation is still gated by the portability audit and no-touch diff budget in `docs/design/database-adapter-implementation-boundary.md`.

If a PostgreSQL path is explicitly approved, it must land as an adapter/runtime infrastructure slice, not as a domain-model rewrite.

This document does not by itself justify abstraction work. Driver, portability audit, migration authority, and verification gates are defined by `docs/design/database-adapter-implementation-boundary.md`.

---

## Boundary Rules

- `runtime/core` use cases are intended to stay DB-dialect independent.
- Repository ports are intended to stay above DB dialects, pending the explicit portability audit.
- DB adapters are infrastructure.
- DB adapters are not portable shared logic.
- Web client never talks to DB directly.
- Source packages never talk to DB directly.
- Docker Compose belongs to deployment layer, not core logic.

`runtime/core/src/db/database.ts` is a Node/SQLite infrastructure adapter, not portable shared logic.

Any future PostgreSQL adapter must satisfy the existing repository and use-case contracts without moving dialect-specific concerns into `src/domain`, `src/application`, or `src/ports`. If that stops being true during audit or implementation, the boundary decision must be reopened rather than widened silently.

---

## Contract Statements

- `runtime/core/src/db/database.ts` is a Node/SQLite infrastructure adapter, not portable shared logic.
- Any future PostgreSQL adapter work, if that candidate is selected, is expected to preserve the same repository/use-case contracts without changing domain or application code, subject to the prerequisite audit gate.
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
