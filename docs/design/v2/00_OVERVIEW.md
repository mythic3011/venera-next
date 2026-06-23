# Venera Platform Design
> Agent context document. Read all files in order before implementing anything.

---

## 0. What Is Venera

Venera is a **Universal Content Platform** — not just a manga reader. The same infrastructure handles comics, webtoons, novels, documents, and notes. Content type is a profile that determines reader mode and available features; it does not change the underlying architecture.

Deployment modes share one `runtime/core`:
- **Standalone** — native desktop/mobile app, local SQLite, no auth required
- **Hosted** — self-hosted web server, PostgreSQL + Redis, auth enforced
- **Microservices** — each Piece runs as its own container (optional, same code, different wiring)

---

## 1. Architecture Layers

```
┌─────────────────────────────────────────────────────────┐
│  Shell (apps/standalone, apps/hosted, apps/web-demo)    │
├─────────────────────────────────────────────────────────┤
│  Adapter Layer  (HTTP routes, WS, Electron IPC)         │
├─────────────────────────────────────────────────────────┤
│  Piece Assembly (DI wiring, topology selection)         │
├───────────────────────┬─────────────────────────────────┤
│  Application Layer    │  Ports (interfaces only)        │
│  (Use Cases)          │  No framework imports here      │
├───────────────────────┤                                 │
│  Domain Layer         │                                 │
│  (Entities/Invariants)│                                 │
└───────────────────────┴─────────────────────────────────┘
```

**Hard rules:**
- `src/domain`, `src/application`, `src/ports` must never import Kysely, SQLite, Express, or any DB/framework
- All DB/framework code lives in adapters beneath the ports
- Auth is adapter-layer concern; core has no user domain model beyond what AuthPort provides

---

## 2. Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Content abstraction | `Content` not `Comic` | Same infra for all content types |
| ID system | UUID v4 for runtime entities (manifest/idempotency IDs are deterministic/composite — see 01) | Immutable, collision-free |
| Section number type | `DecimalString` not `Float` | Avoid 1.4999... floating point |
| Unit ordering | Separate `ContentUnitOrder` + item table | Not delimited strings |
| Reading session | Lifecycle rows; at most ONE active per content (partial unique index) | Simple resume path (`WHERE active`) without destroying lifecycle evidence; Clear marks `abandoned` |
| Log format | OpenTelemetry Log Data Model | One format, no custom parsers |
| Privacy | Schema-level (never log PII fields) | Cannot leak what isn't in schema |
| Auth tokens | Opaque random bearer tokens/API keys with selector + `HMAC-SHA256(verifier)` storage, not JWT | Fast indexed lookup, immediate revoke/rotate, no JWT claim drift |
| Crypto primitives | Always use library, never implement | argon2, @simplewebauthn, arctic |
| Plugin trust | Three-tier (official/community/custom) | One-button install for normal users |
| Hosted sync | Hosted-only extension, gated by explicit conflict contract | Core persistence stays single-runtime last-write-wins |
| Tag taxonomy | Canonical tags + source mappings | Cross-platform search consistency |

---

## 3. Deployment Topologies

**Standalone (minimal):**
```typescript
createVeneraApp({
  pieces: [SchemaPiece(), EventsPiece(), DatabasePiece({ path: "./venera.db" }),
           ContentPiece(), ReaderPiece(), CollectionsPiece(),
           StoragePiece({ backends: ["local_app_data"] }),
           PluginRuntimePiece(), TelemetryPiece({ mode: "local" })],
  adapter: new ElectronAdapter(),
})
```

**Hosted (full):**
```typescript
createVeneraApp({
  pieces: [...corePieces,
           AuthPiece({ methods: ["passkey","oauth","api_key"] }),
           RateLimitPiece({ store: "redis" }),
           AuditPiece({ externalCheckpoint: true }),
           TelemetryPiece({ mode: "otel" }),
           AdminPiece(), SetupPiece(), WsPiece()],
  adapter: new ExpressAdapter({ port: 3000 }),
})
```

**Microservices (split):**
- Same Piece code, different DI wiring per service
- `HttpAuthAdapter` replaces `LocalAuthAdapter`
- `RedisEventBus` replaces `InMemoryEventBus`
- Each service owns its own DB schema subset

---

## 4. Persistence Strategy & Adapter Boundary

(Condensed from archived v1 `docs/design/archive/v1/production-database-adapter-strategy.md` + `docs/design/archive/v1/database-adapter-implementation-boundary.md`; those remain the long-form historical reference.)

### Deployment-mode persistence split

| Mode | Persistence | Notes |
|---|---|---|
| Dev smoke / tests | SQLite | Ephemeral or local-only is valid |
| Standalone (desktop / Android embedded / single-user) | SQLite | Shell-owned local DB |
| Native iOS/iPadOS shell experiment | SQLite only if a real local DB adapter exists | Browser/PWA stays thin-client |
| Temporary demo runtime | SQLite or `:memory:` | Intentionally non-persistent (`demo-memory`) |
| Hosted / self-hosted web, multi-device, long-running server, multi-user | Server-backed adapter required | PostgreSQL is a candidate, **not a committed roadmap** |

Production web persistence must never be represented as `:memory:` or demo SQLite.

### Hard boundary rules

- `src/domain`, `src/application`, `src/ports` never import Kysely/SQLite/Express/any framework; all dialect code stays beneath the ports.
- The allowed insertion seam for any future backend split is **runtime composition / persistence assembly** (bootstrap that opens DB, runs migrations/seed, assembles repositories). If a backend slice needs edits in domain/application/ports, the seam is wrong — stop and reopen the boundary review.
- "Repository ports stay above DB dialects" is a boundary goal, **not** a proven portability claim: current SQLite surfaces (PRAGMAs, partial unique indexes, `ON CONFLICT` seed, migration semantics) must be audited before any non-SQLite work is approved.
- Prerequisites before any backend split: a concrete product driver; an audit of SQLite-specific query/DDL/seed/migration surfaces; an explicit migration-authority sketch (who owns runners, versioning, divergence); a minimal verification strategy (fixtures, isolation, CI).
- Server-backed hosted persistence does not, by itself, change core reader-position authority. `reading_sessions.version` / `device_id` remain hosted-only extension fields until an explicit multi-device conflict-resolution contract is approved.
- Web client and plugins never talk to the DB directly. DB adapters are infrastructure, not portable shared logic.
- Pre-stable schema may be reset without migration-compatibility tax; backup/PITR is deployment policy, out of scope here.
