# Venera Package Architecture & Piece System

---

## Package Catalogue

All packages have zero circular dependencies. Read the dependency graph before importing.

```
┌──────────────────────────────────────────────────────────────┐
│  LEAF PACKAGES (no venera deps)                              │
│                                                              │
│  @venera/events        ← event name constants + Zod schemas  │
│  @venera/permissions   ← roles, permissions, policies        │
│  @venera/tags          ← canonical tag taxonomy + mappings   │
│  @venera/i18n          ← locales, translations, OpenCC       │
│  @venera/content-profiles ← ContentType + ContentProfile     │
├──────────────────────────────────────────────────────────────┤
│  CORE PACKAGES                                               │
│                                                              │
│  @venera/schema        ← Zod entity schemas (imports events) │
│  @venera/api           ← route + middleware contracts        │
│  @venera/client        ← generated TypeScript API client     │
│  @venera/sdk           ← plugin author SDK                   │
├──────────────────────────────────────────────────────────────┤
│  PIECE PACKAGES                                              │
│                                                              │
│  piece-schema          piece-events      piece-database       │
│  piece-content         piece-reader      piece-collections    │
│  piece-storage         piece-auth        piece-rate-limit     │
│  piece-audit           piece-telemetry   piece-reporting      │
│  piece-ws              piece-admin       piece-setup          │
│  piece-plugin-runtime  piece-plugin-repo piece-cdn            │
│  piece-graph           piece-recommendation piece-fingerprint │
│  piece-fts             piece-annotation  piece-note           │
│  piece-client-network  (standalone only)                     │
├──────────────────────────────────────────────────────────────┤
│  ADAPTER PACKAGES                                            │
│                                                              │
│  adapter-express  adapter-hono  adapter-electron  adapter-test│
│  adapter-sqlite   adapter-postgres  adapter-turso            │
│  adapter-redis    adapter-valkey   adapter-memory            │
│  adapter-crowdsec adapter-cloudflare adapter-noop-security   │
│  adapter-nginx    adapter-caddy    adapter-traefik           │
│  infra-config     ← config file generators (nginx/Caddy etc) │
└──────────────────────────────────────────────────────────────┘
```

---

## @venera/events

Single source of truth for all event names. **Never use raw strings.**

```typescript
// src/streams/content.ts
export const ContentEvents = {
  CREATED:              "content.created",
  METADATA_UPDATED:     "content.metadata_updated",
  REMOVED:              "content.removed",
  DELETED:              "content.deleted",
  RELATIONSHIP_DETECTED:"content.relationship.detected",
} as const
export type ContentEventName = typeof ContentEvents[keyof typeof ContentEvents]

export const ContentEventPayloads = {
  [ContentEvents.CREATED]: z.object({
    contentId:    z.string().uuid(),
    contentType:  z.string(),
    // NO title, NO author — TIER 0 fields
  }),
} satisfies Record<ContentEventName, z.ZodSchema>

// Same pattern for all streams:
// AuthEvents, ReaderEvents, CollectionEvents,
// PluginEvents, AdminEvents, SetupEvents, TelemetryEvents

// Master index
export const AllEventNames = {
  ...ContentEvents,
  ...AuthEvents,
  ...ReaderEvents,
  ...CollectionEvents,
  ...PluginEvents,
  ...AdminEvents,
  ...SetupEvents,
  ...TelemetryEvents,
} as const

export type VeneraEventName = typeof AllEventNames[keyof typeof AllEventNames]

// All constants follow the same pattern:
export const ErrorCodes = { NOT_FOUND: "NOT_FOUND", ... } as const
export const SetupSteps = { OWNER_AUTH: "owner_auth", ... } as const
export const WsCloseCodes = { AUTH_FAILED: 4001, ... } as const
```

---

## @venera/permissions

```typescript
// Single source of truth for all authorization decisions

export const Permissions = {
  CONTENT_CREATE:       "content:create",
  CONTENT_READ:         "content:read",
  CONTENT_UPDATE:       "content:update",
  CONTENT_DELETE:       "content:delete",
  COLLECTIONS_READ:     "collections:read",
  COLLECTIONS_WRITE:    "collections:write",
  READER_READ:          "reader:read",
  READER_WRITE:         "reader:write",
  PLUGINS_READ:         "plugins:read",
  PLUGINS_INSTALL:      "plugins:install",
  PLUGINS_REMOVE:       "plugins:remove",
  STORAGE_READ:         "storage:read",
  STORAGE_CONFIG:       "storage:configure",
  ADMIN_USERS_READ:     "admin:users:read",
  ADMIN_USERS_WRITE:    "admin:users:write",
  ADMIN_SYSTEM_READ:    "admin:system:read",
  ADMIN_SYSTEM_WRITE:   "admin:system:write",
  ADMIN_AUDIT_READ:     "admin:audit:read",
  ADMIN_AUDIT_EXPORT:   "admin:audit:export",
  REPORTS_SUBMIT:       "reports:submit",
} as const
export type Permission = typeof Permissions[keyof typeof Permissions]

export const Roles = {
  OWNER:  "owner",
  ADMIN:  "admin",
  VIEWER: "viewer",
  PLUGIN: "plugin",
  SYSTEM: "system",
} as const
export type Role = typeof Roles[keyof typeof Roles]

const ALL = Object.values(Permissions)

export const RolePolicies: Record<Role, Permission[]> = {
  owner:  ALL,
  admin:  ALL.filter(p => !p.startsWith("admin:users:write") && !p.startsWith("admin:system:write")),
  viewer: [Permissions.CONTENT_READ, Permissions.COLLECTIONS_READ, Permissions.READER_READ, Permissions.READER_WRITE, Permissions.REPORTS_SUBMIT],
  plugin: [Permissions.CONTENT_READ, Permissions.PLUGINS_READ],
  system: ALL,
}

export class PolicyEngine {
  can(subject: AuthContext, permission: Permission): boolean {
    const rolePerms = RolePolicies[subject.role]
    if (!rolePerms.includes(permission)) return false
    if (subject.method === "api_key" && !subject.scopes.includes(permission)) return false
    if (subject.role === Roles.PLUGIN && !subject.pluginScopes?.includes(permission)) return false
    return true
  }

  authorize(subject: AuthContext, permission: Permission): void {
    if (!this.can(subject, permission)) {
      throw new ApiError(ErrorCodes.SCOPE_DENIED, {
        required: permission,
        role: subject.role,
      })
    }
  }
}
```

---

## @venera/tags

```typescript
// Canonical tag taxonomy
export const CanonicalTags = {
  "genre:action":        { ns: "genre",    key: "action"    },
  "genre:romance":       { ns: "genre",    key: "romance"   },
  "genre:fantasy":       { ns: "genre",    key: "fantasy"   },
  "genre:horror":        { ns: "genre",    key: "horror"    },
  "genre:scifi":         { ns: "genre",    key: "scifi"     },
  "genre:slice_of_life": { ns: "genre",    key: "slice_of_life" },
  "audience:shounen":    { ns: "audience", key: "shounen"   },
  "audience:shoujo":     { ns: "audience", key: "shoujo"    },
  "audience:seinen":     { ns: "audience", key: "seinen"    },
  "audience:josei":      { ns: "audience", key: "josei"     },
  "status:ongoing":      { ns: "status",   key: "ongoing"   },
  "status:completed":    { ns: "status",   key: "completed" },
  "status:hiatus":       { ns: "status",   key: "hiatus"    },
  // Add more as needed
} as const
export type CanonicalTagKey = keyof typeof CanonicalTags

// Source provider mappings (plugins can register their own)
export const SourceMappings: Record<string, Record<string, CanonicalTagKey>> = {
  copymanga: { "热血": "genre:action", "恋爱": "genre:romance", /* ... */ },
  mangadex:  { "Action": "genre:action", "Romance": "genre:romance", /* ... */ },
}

export function normalizeTag(sourceKey: string, rawTag: string): CanonicalTagKey | null {
  return SourceMappings[sourceKey]?.[rawTag] ?? null
}
```

---

## @venera/i18n

```typescript
export const SupportedLocales = ["en","zh-HK","zh-TW","zh-CN","ja","ko","es","fr","pt-BR","ar"] as const
export type Locale = typeof SupportedLocales[number]
export const RtlLocales: Locale[] = ["ar"]

// Tag labels in multiple locales
export const TagLabels: Record<CanonicalTagKey, Partial<Record<Locale, string>>> = {
  "genre:action":     { en: "Action", "zh-HK": "動作", "zh-CN": "动作", ja: "アクション", ko: "액션" },
  "audience:shounen": { en: "Shounen", "zh-HK": "少年", ja: "少年", ko: "소년" },
  "status:ongoing":   { en: "Ongoing", "zh-HK": "連載中", "zh-CN": "连载中", ja: "連載中" },
}

// zh-HK ↔ zh-CN conversion (uses opencc-js)
import { Converter } from "opencc-js"
export const ChineseConverters = {
  "hk→cn": Converter({ from: "hk", to: "cn" }),
  "cn→hk": Converter({ from: "cn", to: "hk" }),
  "tw→cn": Converter({ from: "tw", to: "cn" }),
  "cn→tw": Converter({ from: "cn", to: "tw" }),
}

// Search query expansion: one query → all Chinese variants
export function expandSearchQuery(query: string, locale: Locale): string[] {
  const variants = new Set([query])
  if (locale === "zh-HK" || locale === "zh-TW") variants.add(ChineseConverters["hk→cn"](query))
  if (locale === "zh-CN") {
    variants.add(ChineseConverters["cn→hk"](query))
    variants.add(ChineseConverters["cn→tw"](query))
  }
  return [...variants]
}

// Tag label with zh fallback chain
export function getTagLabel(tag: CanonicalTagKey, locale: Locale): string {
  return TagLabels[tag]?.[locale]
    ?? (locale === "zh-HK" ? TagLabels[tag]?.["zh-TW"] ?? TagLabels[tag]?.["zh-CN"] : undefined)
    ?? TagLabels[tag]?.["en"]
    ?? tag
}
```

---

## @venera/content-profiles

```typescript
export enum ReaderMode {
  PAGE_FLIP = "page_flip",  // comic horizontal
  SCROLL    = "scroll",     // webtoon vertical
  TEXT_FLOW = "text_flow",  // novel reflowable
  PDF       = "pdf",        // fixed layout
  MARKDOWN  = "markdown",   // note rendering
}

export const ContentProfiles: Record<ContentType, ContentProfile> = {
  comic:    { defaultReaderMode: ReaderMode.PAGE_FLIP, unitType: "image",    supportsFullTextSearch: false, supportsAnnotations: false, supportsWikiLinks: false },
  webtoon:  { defaultReaderMode: ReaderMode.SCROLL,    unitType: "image",    supportsFullTextSearch: false, supportsAnnotations: false, supportsWikiLinks: false },
  novel:    { defaultReaderMode: ReaderMode.TEXT_FLOW,  unitType: "text",     supportsFullTextSearch: true,  supportsAnnotations: true,  supportsWikiLinks: false },
  document: { defaultReaderMode: ReaderMode.PDF,        unitType: "pdf_page", supportsFullTextSearch: true,  supportsAnnotations: true,  supportsWikiLinks: false },
  note:     { defaultReaderMode: ReaderMode.MARKDOWN,   unitType: "markdown", supportsFullTextSearch: true,  supportsAnnotations: true,  supportsWikiLinks: true  },
  article:  { defaultReaderMode: ReaderMode.TEXT_FLOW,  unitType: "html",     supportsFullTextSearch: true,  supportsAnnotations: true,  supportsWikiLinks: false },
}
```

---

## Piece Interface

```typescript
// Every piece follows this interface
interface VeneraPiece<TConfig = void, TProvides = {}> {
  name:    string
  version: string
  requires?: VeneraPiece<any, any>[]
  provides?: (keyof TProvides)[]
  routes?:    VeneraRouter[]
  middleware?: Middleware[]
  migrations?: Migration[]
  init(config: TConfig, ctx: PieceContext): Promise<TProvides>
  dispose?(): Promise<void>
}

// DI Container
class VeneraContainer {
  bind<T>(token: Token<T>, factory: (c: VeneraContainer) => T, singleton = true): this
  get<T>(token: Token<T>): T
}

// DI Tokens
export const Tokens = {
  ContentRepo:    token<ContentRepositoryPort>   ("ContentRepository"),
  SectionRepo:    token<SectionRepositoryPort>   ("SectionRepository"),
  UnitRepo:       token<ContentUnitRepositoryPort>("UnitRepository"),
  ReadingRepo:    token<ReadingSessionRepositoryPort>("ReadingRepository"),
  AuditRepo:      token<AuditEventRepositoryPort>("AuditRepository"),
  AuthPort:       token<AuthPort>                ("AuthPort"),
  EventBus:       token<EventBusPort>            ("EventBus"),
  RateLimiter:    token<RateLimiterPort>         ("RateLimiter"),
  Security:       token<SecurityPort>            ("Security"),
  PolicyEngine:   token<PolicyEngine>            ("PolicyEngine"),
  VectorSearch:   token<VectorSearchPort>        ("VectorSearch"),
  ContentUseCases:token<ContentUseCases>         ("ContentUseCases"),
  ReaderUseCases: token<ReaderUseCases>          ("ReaderUseCases"),
} as const
```

---

## Route Definition Pattern

```typescript
// @venera/api — framework-agnostic route definition

export const ContentRouter = defineRouter({
  prefix: "/api/v1/content",
  routes: {
    getById: defineRoute({
      method:     "GET",
      path:       "/:id",
      permission: Permissions.CONTENT_READ,
      params:     z.object({ id: z.string().uuid() }),
      output:     ContentSchema,
      rateLimit:  "api.content.read",
      handler:    async (ctx) => ctx.useCases.content.getById(ctx.params.id),
    }),
    create: defineRoute({
      method:     "POST",
      path:       "/",
      permission: Permissions.CONTENT_CREATE,
      body:       CreateContentInputSchema,
      output:     ContentSchema,
      rateLimit:  "api.content.write",
      handler:    async (ctx) => ctx.useCases.content.create(ctx.body),
    }),
  },
})

// Middleware pipeline (composition, not if-else)
export const DefaultPipeline = [
  CorrelationMiddleware,    // 1. assign correlationId
  SecurityMiddleware,       // 2. CrowdSec / IP check
  AuthMiddleware,           // 3. validate token + resolve AuthContext
  RateLimitMiddleware,      // 4. check rate limit
  ValidationMiddleware,     // 5. Zod validate body/params/query
  AuditMiddleware,          // 6. record after handler succeeds
] as const
```

---

## Networking Policies

```typescript
export const TimeoutPolicy = {
  default:         30_000,
  pluginFetch:     15_000,
  archiveDownload: 300_000,
  healthCheck:     5_000,
  reportSend:      10_000,
  dbQuery:         5_000,
} as const

export const RetryPolicy = {
  maxAttempts: 3,
  baseDelayMs: 500,
  maxDelayMs:  10_000,
  multiplier:  2,
  jitter:      true,
  retryOn:     [408, 429, 500, 502, 503, 504],
  neverRetry:  [400, 401, 403, 404, 409, 422],
} as const

export const RateLimits = {
  "auth.login":          { window: "1m",  max: 5,   key: "loginId+ip" },
  "auth.passkey.verify": { window: "5m",  max: 10,  key: "ip"         },
  "api.content.read":    { window: "1m",  max: 300, key: "userId"     },
  "api.content.write":   { window: "1m",  max: 60,  key: "userId"     },
  "api.plugins.install": { window: "1h",  max: 20,  key: "userId"     },
  "ws.ticket.issue":     { window: "1m",  max: 20,  key: "userId"     },
  "plugin.fetch":        { window: "1m",  max: 60,  key: "pluginKey+domain" },
  "telemetry.ingest":    { window: "1h",  max: 12,  key: "instanceId" },
} as const
```

---

## Infrastructure Adapters

Every infrastructure component is an adapter behind a port interface:

```typescript
// Security port
interface SecurityPort {
  checkRequest(req: IncomingRequest): Promise<SecurityDecision>
  report(event: SecurityEvent): Promise<void>
}
// Adapters: CrowdSecAdapter | CloudflareAdapter | NoopSecurityAdapter

// EventBus port
interface EventBusPort {
  publish<T extends VeneraEventName>(event: T, payload: EventPayload<T>): Promise<void>
  subscribe<T extends VeneraEventName>(event: T, handler: EventHandler<T>): Unsubscribe
}
// Adapters: InMemoryEventBus | RedisEventBus | NatsEventBus

// VectorSearch port
interface VectorSearchPort {
  upsertVector(contentId: string, vectors: ContentVectors): Promise<void>
  findSimilarByTitle(embedding: Float32Array, opts: SearchOpts): Promise<ScoredContent[]>
  findSimilarByCover(embedding: Float32Array, opts: SearchOpts): Promise<ScoredContent[]>
}
// Adapters: SqliteVecAdapter (standalone) | PgVectorAdapter (hosted)

// All infra swappable at wiring time, zero business logic changes
```
