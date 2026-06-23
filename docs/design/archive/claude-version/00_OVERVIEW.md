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
| ID system | UUID v4 everywhere | Immutable, collision-free |
| Chapter number type | `DecimalString` not `Float` | Avoid 1.4999... floating point |
| Page ordering | Separate `ContentUnitOrder` table | Not delimited strings |
| Reader session | One row per content (upsert) | Simplicity over history |
| Log format | OpenTelemetry Log Data Model | One format, no custom parsers |
| Privacy | Schema-level (never log PII fields) | Cannot leak what isn't in schema |
| Auth tokens | HMAC-signed, not JWT | No crypto-agility surprises |
| Crypto primitives | Always use library, never implement | argon2, @simplewebauthn, arctic |
| Plugin trust | Three-tier (official/community/custom) | One-button install for normal users |
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
