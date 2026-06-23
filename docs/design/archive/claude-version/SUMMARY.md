# Venera Platform Design — Document Index (claude-version draft — Superseded)
> **⚠️ SUPERSEDED.** Canonical design is now `docs/design/v2/` — start at `../../v2/SUMMARY.md`. This `claude-version/` draft is retained for reference only; where it conflicts with v2, **v2 wins**.
> Agent: read all files in order before implementing. Do not skip files.

---

## File Map

| File | Contents |
|---|---|
| `00_OVERVIEW.md` | Architecture vision, design decisions, deployment topologies |
| `01_ENTITIES.md` | All entity definitions with invariants |
| `02_PACKAGES_AND_PIECES.md` | Package architecture, Piece system, DI container, route/middleware design |
| `03_DATABASE_SCHEMA.md` | Full SQL schema (SQLite reference) |
| `04_SECURITY_PLUGINS_RECOMMENDATION.md` | Security design, plugin trust tiers, recommendation engine, OTel log format, client network, implementation priority |
| `05_PLUGIN_SYSTEM.md` | Full plugin system: Provider, Importer, Exporter, Storage, Reader, Extension, Theme |
| `06_DOWNLOAD_NOTIF_UPDATE_STATS.md` | Download manager, notifications, content update/refresh, reading stats, search architecture, sync/backup, content filtering, full repository interfaces list |

---

## Critical Invariants (read first)

```
1.  Actor resolution: ALWAYS server-side. NEVER trust client-supplied actor fields.
2.  Secrets: NEVER in configJson, logs, API responses. ALWAYS via secretRef.
3.  Content identity: ALWAYS owned by Content entity. SourceLink is provenance evidence.
4.  Section number: ALWAYS DecimalString. NEVER Float arithmetic.
5.  Reading session: One row per content (UNIQUE constraint). Upserted, never accumulated.
6.  Audit events: NEVER updated or deleted. Repository port must NOT expose these methods.
7.  Plugin permissions: Validated subset of Roles.PLUGIN at install time.
8.  Storage bytes: NEVER assume available from StorageObject alone. Check StoragePlacement.
9.  Auth tokens: NEVER stored plaintext. NEVER logged. NEVER returned after creation.
10. Privacy: Schema-level. TIER 0 fields must not exist in log schema at all.
11. Plugin DB access: NEVER direct. Always via controlled port (ImportStoragePort, etc.).
12. File type detection: ALWAYS magic number. NEVER extension-only.
13. Import repair path: ALWAYS preserve existing contentId to keep reading session + tags.
14. Tag normalization: ALWAYS slugify (spaces → underscores). Store displayKey separately.
15. zh-HK/zh-TW labels: auto-generated via OpenCC from zh-CN. Mark source as "auto_opencc".
```

---

## Key Naming Conventions

```
Old name (do not use)   →   New name
──────────────────────────────────────────────────────
Comic                   →   Content
ComicId                 →   ContentId
ComicMetadata           →   ContentMetadata
Chapter                 →   ContentSection
ChapterId               →   ContentSectionId
Page                    →   ContentUnit
PageId                  →   ContentUnitId
PageOrder               →   ContentUnitOrder
PageOrderItem           →   ContentUnitOrderItem
ReaderSession           →   ReadingSession
ChapterSourceLink       →   SectionSourceLink
comic_id (column)       →   content_id
chapter_id (column)     →   section_id
page_id (column)        →   unit_id
is_active (boolean)     →   status (enum)
isPrimary (boolean)     →   displayOrder (integer)
orderKey                →   removed, use orderType only
pageCount cache         →   removed, derive from items
```

---

## Package Dependency Order

```
Install / build in this order:

1. @venera/events             (zero deps)
2. @venera/permissions        (zero deps)
3. @venera/tags               (zero deps, uses opencc-js)
4. @venera/i18n               (depends on @venera/tags)
5. @venera/content-profiles   (zero deps)
6. @venera/schema             (depends on @venera/events, zod)
7. @venera/api                (depends on @venera/schema, @venera/permissions)
8. @venera/sdk                (depends on @venera/events, @venera/schema)
9. @venera/client             (depends on @venera/api, @venera/schema)

10. adapters/* (adapter-sqlite, adapter-postgres, adapter-express, etc.)
11. pieces/*   (piece-content, piece-auth, piece-import, etc.)
12. importers/* (@venera/importer-archive, @venera/importer-epub, etc.)
```

---

## Implementation Priority

### P0 — Build first (everything depends on these)
1. `@venera/events` — event name constants, error codes
2. `@venera/permissions` — roles, permissions, PolicyEngine
3. `@venera/tags` — tag taxonomy, normalizeTagKey
4. `@venera/i18n` — locales, OpenCC converters
5. `@venera/content-profiles` — ContentType, ContentProfile
6. `@venera/schema` — Zod schemas for all entities
7. Database schema (all tables from `03_DATABASE_SCHEMA.md`)
8. Repository ports (interfaces only, no implementation)
9. SQLite adapter

### P1 — Core domain
10. Content use cases (Create, Update, Remove, Delete)
11. ContentSection use cases
12. ContentUnit use cases
13. ReadingSession use cases (Open, UpdatePosition, Clear)
14. UserCollection use cases
15. SourceLink + SectionSourceLink CRUD

### P2 — API & Auth
16. `@venera/api` route definitions + middleware
17. Auth (Passkey via @simplewebauthn, OAuth via arctic, API keys)
18. Setup wizard (first-run flow)
19. OpenAPI spec generation

### P3 — Plugin system
20. Plugin manifest validation
21. Plugin install pipeline (download → verify → PackageStore → SourcePlatform)
22. Plugin worker runtime + PluginProxy
23. `defineProvider` in `@venera/sdk`
24. `defineImporter` + official importers (@venera/importer-archive, -pdf, -epub)
25. `defineExporter` + official exporters
26. Plugin Console WebSocket

### P4 — Features
27. Download manager
28. Content update/refresh scheduler
29. Notification system
30. Smart collections
31. Library health check
32. Reader settings (per-content override)
33. Content relationships + proposal queue
34. Creator + SourceCreator

### P5 — Intelligence
35. ContentFingerprint computation (pHash)
36. ContentVector (title embeddings via multilingual-e5-small)
37. sqlite-vec / pgvector setup
38. Graph walk recommendations (Phase 1)
39. Collection co-occurrence CF (Phase 2)
40. Tag system full import (MangaDex API + EhTagTranslation)

### P6 — Advanced
41. Full-text search (SQLite FTS5)
42. ContentAnnotation (highlight/comment)
43. NoteLink / backlinks (note content type)
44. ClientNetworkPiece (proxy/DNS for standalone)
45. Community CDN participation
46. Reading statistics + streak
47. Tamper-evident audit log (hash chain + external checkpoint)

---

## Glossary

```
Content          Universal content item (comic, novel, document, note, etc.)
ContentSection   Structural unit within content (chapter, episode, section)
ContentUnit      Atomic reading unit (image page, text paragraph, PDF page)
SourceLink       Platform provenance edge linking Content to remote work ID
SectionSourceLink Platform provenance edge linking ContentSection to remote chapter ID
SourceCreator    Platform-specific creator credit (uploader, artist credit on platform)
Creator          Canonical creator identity (real-world person/organization)
SourceTag        Raw platform tag (evidence, with optional canonical mapping)
CanonicalTag     Normalized universal tag (namespace:slug format)
StorageObject    Logical file metadata (existence ≠ byte availability)
StoragePlacement Physical location of StorageObject on a backend
ContentVector    ML embeddings for similarity search
ContentRank      PageRank-style score from relationship graph
SmartCollection  Dynamic collection with rule-based auto-population
PreflightDecision Import conflict resolution decision (create_new/repair_existing/conflict_*)
PluginProxy      Runtime component that validates + rate-limits all plugin outbound calls
AuditStream      Named sequence of tamper-evident append-only audit events
TrustTier        Plugin trust level: official | community | custom | unverified
```
