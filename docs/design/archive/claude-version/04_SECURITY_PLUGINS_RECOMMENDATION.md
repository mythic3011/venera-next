# Venera: Security, Plugin System, Recommendation & Implementation Priority

---

## Security Design

### Threat Model

| Actor | Goal | Vectors | Defence Layers |
|---|---|---|---|
| Malicious plugin | Exfiltrate credentials / content | Network calls, config access | Plugin permission model; secretRef never in plugin scope |
| Compromised CDN node | Serve malicious package | Archive replacement | Signed index + archive SHA-256 verify (trust from signature, not server) |
| Insider (self-hosted) | Tamper audit log | Direct DB write | Append-only repo; external checkpoint; HMAC signature |
| Auth bypass | Unauthorized access | Stolen token | Short TTL; HMAC tokens; ipHash anomaly detection |
| Automated scanner | Enumerate users / content | Brute force | Rate limit by (userId, IP) tuple |
| Plugin replay | Re-run stale install | Old manifest | event_id dedup; archiveSha256 + version conflict check |

**Defence-in-depth rule:** Each attack must beat at least **two** independent layers.

### Privacy Tiers (Log/Report fields)

```
TIER 0 — NEVER appears in any log, report, or telemetry:
  configJson, secretRef
  content title, collection name, display title
  description, author name
  pageId / unitId / sectionId (reading position)
  result_json from idempotency records
  raw search queries
  remote URLs (sanitized pattern only)
  user email (hashed only)

TIER 1 — One-way hash before logging:
  searchQuery → sha256(query).slice(0,8) as query_hash
  normalizedTitle → sha256(title).slice(0,8) as title_hash
  IP address → sha256(ip) as ip_hash

TIER 2 — Safe to log as-is:
  contentId (internal UUID, no content meaning)
  errorCode, pluginKey, httpStatus, durationMs
  runtimeVersion, platform, deploymentMode
  sessionId (anonymous, rotates daily)
```

### Security Headers (hosted mode)

```
Content-Security-Policy: default-src 'self'; script-src 'nonce-{per_request_nonce}'
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
X-Venera-Request-Id: {correlationId}
```

### Tamper-Evident Audit Log

Every audit event forms a hash chain per stream:

```
eventCore = canonicalJSON({ metadata + prevHash + payloadHash })
eventHash = SHA-256(eventCore)
signature = HMAC-SHA256(eventHash, signingKey)

Detection:
  - Modify payload  → payloadHash mismatch
  - Delete middle   → seq gap + prevHash mismatch
  - Replay event    → event_id UNIQUE constraint
  - Forge actor     → actor resolved server-side, never from request
  - Tail delete     → external checkpoint merkle root mismatch
```

Audit streams:
```
"auth"              ← all auth events (highest sensitivity)
"content_management"← content CRUD
"reader"            ← reading session changes
"plugin.install"    ← package lifecycle
"plugin.{key}"      ← per-plugin events
"admin"             ← admin actions
"setup"             ← instance setup steps
"telemetry.consent" ← consent changes
```

---

## Plugin System

### Trust Tiers

```
Tier 0 — Official
  Signed by maintainer key + counter-signed by official repo
  Pre-audited, automated CI/CD checks
  UI: [Install] ✓ Verified

Tier 1 — Community
  Signed by publisher key (vpm-signer / Ed25519)
  Basic automated checks
  UI: [Install] ⚠ Community

Tier 2 — Custom / Self
  Unsigned or self-signed
  UI: [Install (Advanced)] + confirmation dialog

Trust is verified cryptographically, not by server identity.
Mirrors are untrusted byte relays; trust comes from signatures.
```

### Plugin Layers

```
Layer 0 — Declarative (YAML, no code):
  key, displayName, version
  search.url, search.items.selector, ...
  chapters.url, chapters.items.selector, ...

Layer 1 — SDK (TypeScript, minimal code):
  import { defineProvider } from "@venera/sdk"
  SDK handles: timeout, retry, rate limit, error wrapping, return validation

Layer 2 — Full (arbitrary TypeScript):
  Full access to permitted SDK APIs
  Declared permissions validated at install time
```

### Plugin Manifest Required Fields

```typescript
interface PluginManifest {
  key:             string    // unique, stable
  providerKey:     string    // identity metadata only
  version:         string    // semver
  archiveSha256:   string    // lowercase hex
  runtimeRequires: string    // semver range e.g. ">=0.5.0"
  apiLevel:        number
  pluginLayer:     "declarative" | "sdk" | "full"
  contentTypes:    ContentType[]
  permissions:     Permission[]  // declared subset of Roles.PLUGIN allowed perms
  trustTier:       "official" | "community" | "custom" | "unverified"
  publisherKeyFingerprint?: string
  reportEndpoint?: string
  i18n?: { defaultLocale: Locale; messages: Record<Locale, Record<string, string>> }
}
```

### Plugin Lifecycle

```
repository entry
  → verify index signature (Ed25519 public key)
  → verify package entry signature (publisher key from index)
  → download archive bytes (any mirror)
  → verify archiveSha256 against signed index entry
  → integrity verifier (pure in-memory, no I/O)
  → PackageStore commit (atomic, no partial state)
  → source_platform mutation (only after commit succeeds)
  → cleanup staging

Failure semantics:
  - PackageStore commit failure → no durable partial state
  - source_platform mutation failure → rollback OR mark orphaned
  - Orphaned artifacts → deterministic cleanup queue
  - Stuck "committed" (process crash) → TTL detection policy needed
```

### Plugin SDK Error Codes

```typescript
enum PluginErrorCode {
  NETWORK_TIMEOUT     = "NETWORK_TIMEOUT",
  NETWORK_BLOCKED     = "NETWORK_BLOCKED",
  RATE_LIMITED        = "RATE_LIMITED",
  AUTH_REQUIRED       = "AUTH_REQUIRED",
  PARSE_CONTENT_LIST  = "PARSE_CONTENT_LIST",
  PARSE_SECTIONS      = "PARSE_SECTIONS",
  PARSE_UNITS         = "PARSE_UNITS",
  SELECTOR_NO_MATCH   = "SELECTOR_NO_MATCH",
  INVALID_RETURN_TYPE = "INVALID_RETURN_TYPE",
  MISSING_REQUIRED    = "MISSING_REQUIRED",
  RUNTIME_VERSION     = "RUNTIME_VERSION",
  API_REMOVED         = "API_REMOVED",
}
// All errors carry: code, message, hint (human-readable fix), debugInfo (TIER 2 only)
```

---

## Recommendation Engine

### Graph Structure

```
Nodes: ContentNode, TagNode, CollectionNode
Edges:
  ContentRelationship  (weight: manual=1.0, auto_high=0.8, auto_low=0.4)
  ContentTag           (weight: manual=1.0, auto=0.7)
  CollectionMembership (recency + pinned signals)
  ReadingEdge          (completionRate, sessionCount, lastReadAt)
```

### Algorithms (in implementation order)

**Phase 1 — Graph Walk (no ML):**
```
Node2Vec random walk on ContentRelationship graph
  → comics reached in fewer steps = more related
ContentRank (PageRank variant)
  → content collected/linked more = higher importance
```

**Phase 2 — Collaborative Filtering:**
```
Collection co-occurrence matrix
  → content appearing in same collections = related
Item-item CF on reading history
  → content often read in sequence = related
```

**Phase 3 — Two-Tower (ML):**
```
Tower 1 (candidate generation):
  user embedding = avg(reading history content embeddings)
  ANN search: find top-K candidates by cosine similarity

Tower 2 (ranking):
  score = weighted combination of:
    embedding_similarity × 0.35
    completion_rate       × 0.25
    graph_distance        × 0.20
    content_rank          × 0.10
    recency               × 0.10
```

### Training Signals

```typescript
// Explicit (strongest)
"relationship_confirmed"   → positive training pair
"relationship_rejected"    → negative training pair
"collection_grouped"       → implicit similarity

// Implicit
"reading_progress"         → completionRate signal
"recommendation_click"     → (source, target) positive pair
"recommendation_dismiss"   → negative pair
"search_click"             → (query, content) relevance
```

### Self-Learning Loop

```
User links content A ↔ content B as "translation"
  → TrainingSignal recorded
  → Model learns: this pattern (similar title + same structure + diff lang) = translation
  → RelationshipDetector re-scores similar pairs
  → Proposes more relationships with higher confidence
  → User confirms/rejects → more signals → model improves
```

### Vector Storage

```sql
-- SQLite (standalone): sqlite-vec extension
-- PostgreSQL (hosted): pgvector extension

-- Cosine similarity query
SELECT content_id, vec_distance_cosine(title_vec, ?) AS distance
FROM content_vectors ORDER BY distance ASC LIMIT 20;

-- PostgreSQL with HNSW index
CREATE INDEX ON content_vectors USING hnsw (title_vec vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);
```

### Privacy

```
Standalone: all training local, model stays on device
Hosted:     model trained per-instance, no cross-instance sharing
Community:  anonymized aggregate co-occurrence only (k-anonymity threshold = 5)
            session_id rotates daily, stripped at gateway
```

---

## Log Format (OTel-compatible)

All logs must use this format. No custom log formats anywhere.

```typescript
interface VeneraLogEntry {
  timestamp:   string          // ISO 8601 UTC
  severity:    "TRACE"|"DEBUG"|"INFO"|"WARN"|"ERROR"|"FATAL"
  traceId:     string          // = correlationId
  spanId:      string

  resource: {
    "service.name":    "venera-runtime"
    "service.version": string
    "deployment.mode": "standalone" | "hosted"
    "platform":        string
  }

  body: string                 // human-readable, NO sensitive data

  // ONLY pre-approved attribute keys
  attributes: {
    "venera.boundary"?:       string
    "venera.event_name"?:     string
    "venera.correlation_id"?: string
    "venera.error_code"?:     string
    "venera.plugin_key"?:     string
    "venera.plugin_version"?: string
    "venera.duration_ms"?:    number
    "venera.http_status"?:    number
    "venera.query_hash"?:     string   // hash of query, NOT raw query
    // NO content titles, NO user data, NO credentials
  }
}
```

---

## Client Network (Standalone Only)

```typescript
// Proxy config
interface ProxyConfig {
  name: string
  type: "http" | "https" | "socks5"
  host: string
  port: number
  auth?: { username: string; password: string }  // stored via secretRef
}

// DNS config
interface DnsConfig {
  mode: "system" | "custom" | "doh" | "dot"
  servers?: string[]
  dohUrl?: string
  dotHost?: string
  cache: boolean
  ttl: number
}

// Routing rule (Clash-style)
interface NetworkRule {
  type:   "DOMAIN" | "DOMAIN-SUFFIX" | "DOMAIN-KEYWORD" | "IP-CIDR" | "GEOIP"
  value:  string
  policy: "DIRECT" | "PROXY" | string   // string = named proxy
}

// Plugin fetch() calls go through ClientNetworkPiece automatically
// Per-source platform overrides supported
// Burst limit: 5 req/sec per plugin per domain
// Sustained limit: 60 req/min per plugin per domain
```

---

## Implementation Priority

Implement in this order. Do not skip layers.

### Priority 0 — Foundations (implement first, everything else depends on these)
1. `@venera/events` — all event constants, error codes, setup steps
2. `@venera/permissions` — roles, permissions, policies, PolicyEngine
3. `@venera/tags` — canonical taxonomy, source mappings
4. `@venera/i18n` — locales, tag labels, OpenCC converters
5. `@venera/content-profiles` — ContentType, ContentProfile, ReaderMode
6. `@venera/schema` — Zod schemas for all entities

### Priority 1 — Core Domain
7. Database schema (all tables from 03_DATABASE_SCHEMA.md)
8. Repository ports (interfaces only, no implementation)
9. SQLite adapter (implements all ports for standalone)
10. Content use cases: Create, UpdateMetadata, Remove, PermanentDelete
11. ContentSection use cases: CreateFromImport
12. ContentUnit use cases: basic CRUD
13. ReadingSession use cases: Open, UpdatePosition, GetPosition, Clear

### Priority 2 — API & Middleware
14. `@venera/api` — defineRoute, defineRouter, defineMiddleware
15. All middleware: Correlation, Auth, RateLimit, Validation, Audit
16. All routers: Content, Collections, Reader, Plugins, Reports
17. OpenAPI spec generation from schemas
18. `@venera/client` — TypeScript API client

### Priority 3 — Auth & Setup (hosted mode)
19. Auth entities + SQLite adapter
20. Passkey auth (uses @simplewebauthn/server)
21. OAuth auth (uses arctic)
22. API key management
23. SetupPiece — first-run wizard with setup token
24. AdminPiece — user management, system health

### Priority 4 — Plugin System
25. SourceRepository + trust tier verification
26. Plugin download + integrity verification pipeline
27. PackageStore (committed → active → orphaned → cleanup_pending → removed)
28. PluginRuntimePiece — load, execute, sandbox
29. Plugin SDK (@venera/sdk) — defineProvider, PluginError, rate-limited fetch
30. Plugin Console (WebSocket streaming)

### Priority 5 — Recommendation & Graph
31. ContentFingerprint computation (pHash, chapter structure)
32. ContentRelationship CRUD + proposal queue
33. ReadingEvent recording
34. Graph walk (Phase 1, no ML)
35. Collection co-occurrence CF (Phase 2)
36. Vector search setup (sqlite-vec for standalone, pgvector for hosted)
37. Title embedding (multilingual-e5-small)
38. Two-tower ranking (Phase 3)

### Priority 6 — Advanced Features
39. Full-text search (SQLite FTS5 for text content types)
40. ContentAnnotation (highlight/comment for text content)
41. NoteLink / backlinks (note content type)
42. ClientNetworkPiece (standalone proxy/DNS)
43. Community CDN participation (opt-in)
44. Community telemetry gateway

### Priority 7 — Observability
45. Tamper-evident audit log with hash chain
46. External checkpoint store
47. OTel integration (logs → Loki, metrics → Prometheus, traces → Tempo)
48. Crashlytics-style reporting (opt-in)
49. TelemetryConsent flow

---

## Key Invariants to Enforce Everywhere

```
1. Actor resolution: ALWAYS server-side. NEVER trust client-supplied actor fields.
2. Secrets: NEVER in configJson, logs, or API responses. ALWAYS via secretRef.
3. Content identity: ALWAYS owned by Content entity. SourceLink is provenance evidence.
4. Section number: ALWAYS DecimalString. NEVER Float arithmetic for comparison.
5. Reading session: ALWAYS upserted (one row per content). NEVER accumulated.
6. Audit events: NEVER updated or deleted. Repository port must not expose these methods.
7. Plugin permissions: ALWAYS validated subset of Roles.PLUGIN at install time.
8. Storage bytes: NEVER assume available from StorageObject alone. Check StoragePlacement.
9. Auth tokens: NEVER stored plaintext. NEVER logged. NEVER returned after creation.
10. Privacy: schema-level. If a field is TIER 0, it must not exist in log schema at all.
```
