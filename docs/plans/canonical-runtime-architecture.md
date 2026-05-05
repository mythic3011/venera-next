# Canonical Runtime Architecture

**Status**: Architecture Baseline (Phase 1)  
**Branch**: `architecture/canonical-skeleton`  
**Date**: May 5, 2026

---

## Overview

This document describes the **Canonical Runtime Architecture** for Venera - a complete rewrite of the legacy codebase using clear ownership boundaries, typed domain models, schema-first design, and security-aware isolation.

### Guiding Principles

1. **String refs are projections, not authority** — Database columns and types own identity
2. **One boundary, one responsibility** — Presentation, Application, Domain, Ports, Infrastructure
3. **Schemas are first-class** — All data structures validated against JSON schemas
4. **Legacy code is quarantined** — Reference only, never authority
5. **Security boundaries explicit** — Who owns what, what can't cross what line
6. **Diagnostics answer decisions** — Not just "what happened" but "why this choice"

---

## Architecture Layers

```
┌─────────────────────────────────────────────────────┐
│ Presentation (UI, Routes, State Management)         │
├─────────────────────────────────────────────────────┤
│ Application / Use Cases (Coordinator, Service)      │
├─────────────────────────────────────────────────────┤
│ Domain (Models, Business Rules, Invariants)         │
├─────────────────────────────────────────────────────┤
│ Ports (Repository, Service Interfaces)              │
├─────────────────────────────────────────────────────┤
│ Infrastructure (DB, Network, File I/O, Adapters)    │
├─────────────────────────────────────────────────────┤
│ Legacy Migration (Reference Code, Extraction)       │
└─────────────────────────────────────────────────────┘
```

### Presentation Layer
- **Responsibility**: Render UI, capture user intent, route navigation
- **Owns**: Screen widgets, state notifiers, navigation logic
- **Cannot**: Access database directly, make repository calls (→ use Application layer)
- **Interaction**: Calls Application layer use cases

### Application / Use Case Layer
- **Responsibility**: Orchestrate domain logic, manage transactions, coordinate features
- **Owns**: Use case coordination, service logic, business process workflows
- **Cannot**: Access database directly (→ use Ports), import presentation widgets
- **Interaction**: Calls Domain models, invokes Ports (repositories, services)

### Domain Layer
- **Responsibility**: Core business models, rules, invariants
- **Owns**: `Comic`, `Chapter`, `Page`, `ReaderSession`, `SourcePlatform`, `Favorite`, etc.
- **Cannot**: Import framework code (Flutter, Drift), access infrastructure
- **Interaction**: Called by Application layer, used by Infrastructure for mapping

### Ports Layer
- **Responsibility**: Define contracts for repositories and external services
- **Owns**: `ComicRepository`, `ReaderSessionRepository`, `DiagnosticsWriter`, etc.
- **Cannot**: Implement database logic (→ Infrastructure implements)
- **Interaction**: Defined here, implemented in Infrastructure

### Infrastructure Layer
- **Responsibility**: Implement Ports, manage database, handle I/O, adapt external APIs
- **Owns**: Database queries, file operations, HTTP clients, schema migrations
- **Cannot**: Contain business logic (→ belongs in Domain)
- **Interaction**: Implements Ports, called by Application layer

### Legacy Migration Layer
- **Responsibility**: Reference, extraction, gradual replacement
- **Owns**: Old code in `legacy/migration/`, extraction utilities
- **Cannot**: Be imported by canonical code (read-only)
- **Interaction**: One-way dependency - canonical extracts from legacy, never imports

---

## Folder Structure

```
lib/
├── core/                                    # Shared infrastructure
│   ├── database/                            # DB connection, helpers
│   ├── diagnostics/                         # Structured events, exporters
│   ├── security/                            # Security boundaries, policies
│   ├── schema/                              # JSON schema validation
│   ├── result/                              # Result<T> type for error handling
│   └── ids/                                 # EntityId, ComicId, etc.
│
├── features/                                # Feature modules (one per feature)
│   ├── reader/                              # Reader runtime, sessions, contracts
│   │   ├── domain/                          # ReaderSession, ReaderOpenTarget
│   │   ├── application/                     # Use cases (OpenReader, SavePosition, etc.)
│   │   ├── ports/                           # ReaderSessionRepository interface
│   │   ├── infrastructure/                  # Database, session persistence
│   │   └── presentation/                    # Reader UI widgets
│   │
│   ├── comic_library/                       # Comic, chapter, page models
│   │   ├── domain/                          # Comic, Chapter, Page, PageOrder
│   │   ├── application/                     # SearchComics, ListChapters use cases
│   │   ├── ports/                           # ComicRepository, ChapterRepository
│   │   └── infrastructure/                  # DB queries, sync logic
│   │
│   ├── local_import/                        # Local file import pipeline
│   │   ├── domain/                          # ImportBatch, FileValidation
│   │   ├── application/                     # ImportComic, ValidateImport use cases
│   │   ├── ports/                           # ImportRepository interface
│   │   └── infrastructure/                  # File I/O, zip/pdf handling
│   │
│   ├── sources/                             # Source provider management
│   │   ├── domain/                          # SourcePlatform, SourceManifest
│   │   ├── application/                     # ListSources, InstallSource use cases
│   │   ├── ports/                           # SourceRegistry interface
│   │   ├── infrastructure/                  # Manifest loading, validation
│   │   └── sandbox/                         # JS execution sandbox (security boundary)
│   │
│   ├── favorites/                           # Favorite domain and persistence
│   │   ├── domain/                          # Favorite entity
│   │   ├── application/                     # AddFavorite, RemoveFavorite
│   │   ├── ports/                           # FavoriteRepository
│   │   └── infrastructure/                  # DB persistence
│   │
│   └── settings/                            # App preferences/config only
│       ├── domain/                          # AppSettings domain model
│       ├── application/                     # UpdateSetting use cases
│       ├── ports/                           # SettingsRepository
│       └── infrastructure/                  # Local storage, prefs
│
├── legacy/                                  # Quarantined legacy code
│   ├── app/                                 # Old routing, app structure
│   ├── components/                          # Old UI components
│   ├── features/                            # Old feature implementations
│   ├── foundation/                          # Old core layer
│   ├── network/                             # Old network code
│   ├── pages/                               # Old page widgets
│   ├── utils/                               # Old utilities
│   ├── migration/                           # Migration helpers, extraction
│   └── reference/                           # Read-only reference only
│
├── main.dart                                # App entry point
├── init.dart                                # Initialization
└── headless.dart                            # Headless mode
```

---

## Schemas (First-Class Citizens)

All data structures are validated against JSON schemas in `schemas/`:

### `diagnostics_event.schema.json`
Structured diagnostics events with boundary, action, reason:
```json
{
  "event": "reader.route.unresolved_target",
  "level": "warn",
  "boundary": "route.dispatch",
  "action": "rejected",
  "comicId": "uuid",
  "sourceKind": "local",
  "reason": "missing_local_chapter",
  "correlationId": "..."
}
```

### `source_manifest.schema.json`
Provider-specific manifests with endpoint rules, no code:
```json
{
  "version": "1.0.0",
  "provider": "copymanga",
  "displayName": "CopyManga",
  "baseUrl": "https://api.copymanga.com",
  "headers": {...},
  "search": {...},
  "permissions": ["network.http", "storage.cache"]
}
```

### `import_manifest.schema.json`
Import batch metadata with canonical file ordering:
```json
{
  "importBatchId": "uuid",
  "sourceType": "cbz",
  "files": [
    {"path": "001.jpg", "index": 0, "checksum": "..."},
    {"path": "002.jpg", "index": 1, "checksum": "..."}
  ]
}
```

### `reader_event.schema.json`
Reader runtime events (session, page load, navigation).

### `app_settings.schema.json`
User preferences (theme, language, reader settings).

---

## Domain Models

### Comic Library
- **Comic** — unique work, separate from metadata
- **ComicMetadata** — mutable properties (title, cover, description)
- **Chapter** — ordered within comic, links to source chapter
- **Page** — ordered within chapter (0-based), links to source page
- **PageOrder** — reordering policy (source, user override, import detected)

### Reader
- **ReaderSession** — canonical position (chapter_id, page_index, not JSON)
- **ReaderOpenTarget** — request to open a specific position
- **ReaderOpenRequest** — validated open target with correlation ID

### Sources
- **SourcePlatform** — provider (local, remote, virtual)
- **SourceManifest** — provider behavior (endpoints, headers, no code)

### Favorites
- **Favorite** — user's marked work

### Import
- **ImportBatch** — batch metadata with file order
- **FileValidation** — safety checks (bomb detection, magic bytes)

---

## Security Boundaries

### JS Source Sandbox
```
No arbitrary source script authority.

Source scripts may describe provider-specific behavior.
Source scripts may extract data from responses.

Runtime owns:
✓ Network wrapper (HTTP client, timeouts, retries)
✓ Cookie access (session storage, expiration)
✓ Timeout/retry logic (circuit breaker)
✓ Schema validation (response validation)
✓ Logging (diagnostics)
✓ Permission enforcement
✓ Storage access (file I/O)
```

### Source Package Provenance
- Signed manifest required
- Explicit permission declaration
- Code review before installation
- Version-locked (no auto-update)
- Sandboxed from each other

### Cookie/Session Isolation
- Per-source storage
- Encrypted at rest
- Runtime-mediated access
- JS scripts cannot directly access

### Input Validation
- URL scheme validation (http/https)
- JSON schema validation
- File path sanitization (directory traversal)
- String length bounds
- Numeric range checks

### File Import Safety
- Bomb pattern detection
- File header validation (magic bytes)
- Extraction depth limits
- Total size checks
- Isolated temp directory
- Automatic cleanup

### Diagnostics Redaction
- No cookie values
- No auth headers
- Domains logged (not full URLs with query params)
- No user data
- Event type, boundary, action only

---

## Testing Strategy

### 1. Domain Tests
- Model invariants
- No database dependencies
- Pure Dart/logic only

### 2. Repository Tests
- Interface contract validation
- Migration logic
- Data integrity

### 3. Use Case Tests
- Application workflow
- Integration with domain + repositories

### 4. Source Manifest Validation Tests
- Schema validation
- Permission declaration
- Endpoint configuration

### 5. Reader Runtime Smoke Tests
- Session persistence
- Position recovery
- Invalid state rejection

### 6. No-Legacy-Import Architecture Tests
- Verify no canonical code imports legacy
- Use static analysis (ast-grep, analyzer)

---

## Layering Rules (Enforced)

### ✓ Allowed
- Presentation → Application
- Application → Domain, Ports
- Domain → (self only)
- Ports → (interface definitions)
- Infrastructure → Ports (implements)
- Infrastructure → Domain (maps to)
- Legacy → (read-only, extraction only)

### ✗ Forbidden
- Domain → Infrastructure
- Domain → Presentation
- Presentation → Infrastructure (except via Application)
- Canonical → Legacy (imports)
- Infrastructure → Presentation

---

## Migration from Legacy

### Phase 1 (Current)
- ✅ Schema design
- ✅ Domain models
- ✅ Layering architecture
- ✅ Security boundaries

### Phase 2
- Repository implementations
- Database schema creation
- Migration utilities

### Phase 3
- Application use cases
- Ports contract implementation

### Phase 4
- Presentation layer (new widgets)
- Router integration

### Phase 5
- Gradual feature cutover
- Legacy code extraction
- Retirement

---

## Validation Gates

Before any canonical code is merged:

1. **No legacy imports** — ast-grep analysis
2. **Schema validation** — all JSON validated
3. **Layering rules** — no violations
4. **Architecture tests** — domain + repository + smoke tests pass
5. **Diagnostics redaction** — no sensitive data
6. **Security boundary** — no authority leakage

---

## References

- [Canonical Database Model](canonical-db-model.md)
- [Development Branch Strategy](../README.md#development-branch-strategy)
- `schemas/` — JSON schemas for all data structures
- `lib/core/` — Shared types and utilities
