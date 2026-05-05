# Language-Agnostic Design: Complete Specification

**Canonical runtime architecture for Venera - ready for any implementation language (Rust, Go, Kotlin, etc.).**

---

## Design Specification Index

This comprehensive language-agnostic design defines the entire Venera canonical runtime. Choose any implementation language - the architecture remains identical.

### Core Design Documents

| Document | Purpose | Defines |
|----------|---------|---------|
| **entities.md** | Domain models | 10 core entities (Comic, Chapter, Page, ReaderSession, SourcePlatform, etc.) |
| **database-schema.md** | Persistence layer | 9 relational tables with constraints, indexes, cascade behavior |
| **repository-interfaces.md** | Data access contracts | 8 repository interfaces (ComicRepository, ChapterRepository, etc.) with Query + Command operations |
| **use-cases.md** | Business logic | 14 orchestrated workflows (CreateComic, ImportComic, UpdateReaderPosition, etc.) |
| **diagnostics-events.md** | Observability | Complete event schema for audit trail, monitoring, tracing |
| **security-boundaries-layering.md** | Architecture | 5-layer hexagonal architecture with security boundaries between each layer |
| **ipc-protocol-api.md** | External API | Protocol Buffer message schemas for Presentation ↔ Application communication |
| **class-definitions-casting.md** | Type system | Class hierarchies per layer, casting rules, transformation patterns |

---

## Architecture Overview

### 5-Layer Stack

```
┌─────────────────────────────────────────────────────┐
│  PRESENTATION LAYER (Flutter/Dart)                  │
│  - UI models (ComicUI, ReaderViewModel, etc.)       │
│  - User interactions → IPC requests                  │
│  - IPC responses → UI rendering                     │
│  Owns: UI state, animations, local UI logic         │
├─────────────────────────────────────────────────────┤ ⬅️ Security Boundary
│  APPLICATION LAYER (Use Cases)                      │
│  - Orchestrates repositories + domain rules         │
│  - Executes business workflows                      │
│  - Emits DiagnosticsEvents                          │
│  Owns: Request validation, use case logic           │
├─────────────────────────────────────────────────────┤ ⬅️ Security Boundary
│  DOMAIN LAYER (Business Rules)                      │
│  - Pure business entities (Comic, Chapter, Page)    │
│  - Immutable aggregates with invariants             │
│  - No I/O, no databases, no network                 │
│  Owns: Business model, validation rules             │
├─────────────────────────────────────────────────────┤ ⬅️ Security Boundary
│  PORTS LAYER (Interfaces)                           │
│  - Repository interfaces (not implementations!)     │
│  - Input validation, output transformation          │
│  - Error mapping (infra → domain errors)            │
│  Owns: Repository contracts, interface definitions  │
├─────────────────────────────────────────────────────┤ ⬅️ Security Boundary
│  INFRASTRUCTURE LAYER (I/O)                         │
│  - SQLite driver, file I/O, HTTP client             │
│  - Repository implementations                       │
│  - Encryption, connection pooling                   │
│  Owns: Database operations, external services       │
└─────────────────────────────────────────────────────┘
```

### Data Flow (Per Operation)

```
User Action → [PRESENTATION]
              ↓ (Convert to IPC message)
              [IPC Protocol Buffers]
              ↓ (HTTP/gRPC over TLS)
              [APPLICATION] Deserialize + Validate
              ↓ (Transform to Domain entity)
              [DOMAIN] Pure business logic
              ↓ (Call Repository interface)
              [PORTS] Validate + Transform
              ↓ (Execute SQL/I/O)
              [INFRASTRUCTURE] Database/Files
              ↓ (Return database row)
              [PORTS] Transform row → Entity
              ↓ (Return entity)
              [APPLICATION] Emit event
              ↓ (Serialize to IPC)
              [IPC] Response message
              ↓ (HTTP/gRPC response)
              [PRESENTATION] Deserialize + Render UI
              ↓ (Display to user)
```

---

## Entity Relationship Diagram

```
Comic (1) ────→ (N) Chapter
  ├─→ ComicMetadata (1:1, optional)
  ├─→ Favorite (1:1, optional)
  ├─→ ReaderSession (1:1)
  └─→ ImportBatch (1:N, after completion)

Chapter (1) ────→ (N) Page
  ├─→ PageOrder (1:1)
  └─→ SourcePlatform (N:1, optional link)

Page
  └─→ SourcePlatform (N:1, optional link)

SourcePlatform (1) ────→ (N) SourceManifest

ReaderSession
  └─→ Comic (N:1, one per comic)

Favorite
  └─→ Comic (N:1, one per comic)

ImportBatch
  └─→ Comic (N:1, optional, after completion)
```

---

## Core Entities (Summary)

| Entity | Immutable | Unique Key | Parent | Purpose |
|--------|-----------|-----------|--------|---------|
| **Comic** | id, createdAt | normalizedTitle | None | Canonical work identity |
| **ComicMetadata** | None | N/A | Comic | Mutable properties |
| **Chapter** | id, comicId | (comicId, chapterNumber) | Comic | Ordered sequence |
| **Page** | id, chapterId | (chapterId, pageIndex) | Chapter | Image in chapter |
| **ReaderSession** | id, comicId | comicId | Comic | Current position (one per comic) |
| **PageOrder** | id | chapterId | Chapter | Reordering policy |
| **SourcePlatform** | id, canonicalKey | canonicalKey | None | Comic provider |
| **SourceManifest** | id, version | (sourcePlatformId, version) | SourcePlatform | Provider behavior |
| **Favorite** | id, markedAt | comicId | Comic | User's marked work |
| **ImportBatch** | id | (sourceType, sourcePath) | N/A | File import metadata |

---

## Database Layer (9 Tables)

| Table | Primary Key | Foreign Keys | Unique Constraints |
|-------|-------------|--------------|-------------------|
| **comics** | id | None | normalized_title |
| **comic_metadata** | comic_id | comics(id) | comic_id |
| **chapters** | id | comics(id) | (comic_id, chapter_number) |
| **pages** | id | chapters(id) | (chapter_id, page_index) |
| **page_orders** | id | chapters(id) | chapter_id |
| **reader_sessions** | id | comics(id) | comic_id |
| **source_platforms** | id | None | canonical_key |
| **source_manifests** | id | source_platforms(id) | None |
| **favorites** | id | comics(id) | comic_id |
| **import_batches** | id | comics(id) | (source_type, source_path) |

---

## Use Cases (14 Workflows)

### Comic Management
- **UC-001**: Create New Comic
- **UC-002**: Import Comic from File (CBZ, PDF, directory)
- **UC-003**: Update Comic Metadata
- **UC-004**: Delete Comic (cascading)

### Reader Management
- **UC-005**: Read Comic (Update Position)
- **UC-006**: Get Reader Position
- **UC-007**: Clear Reader Position

### Favorites Management
- **UC-008**: Mark Comic as Favorite
- **UC-009**: Unmark Comic as Favorite
- **UC-010**: List Favorites

### Chapter & Page Management
- **UC-011**: Create Chapters from Import
- **UC-012**: Reorder Pages in Chapter

### Search & Browse
- **UC-013**: Search Comics (full-text)
- **UC-014**: List All Comics

---

## Repository Interfaces (8 Repositories)

Each repository provides Query + Command operations:

| Repository | Query Operations | Command Operations |
|------------|------------------|-------------------|
| **ComicRepository** | getComicById, getComicByNormalizedTitle, listAllComics, searchComics | createComic, updateComicMetadata, deleteComic |
| **ChapterRepository** | getChapterById, listChaptersByComic, getChapterByNumber, getChapterCount | createChapter, updateChapter, deleteChapter |
| **PageRepository** | getPageById, listPagesByChapter, getPageByIndex, getPageCount | createPage, createPages, updatePage, deletePage, reindexPages |
| **ReaderSessionRepository** | getReaderSession, listReaderSessions | updateReaderPosition, clearReaderSession |
| **PageOrderRepository** | getPageOrder, getPageOrderType | setUserPageOrder, resetPageOrder |
| **SourcePlatformRepository** | getSourcePlatformById, getSourcePlatformByKey, listAllSourcePlatforms, listEnabledSourcePlatforms | createSourcePlatform, updateSourcePlatform, deleteSourcePlatform |
| **SourceManifestRepository** | getManifestById, getManifestByPlatform, listManifestsByPlatform | createManifest |
| **FavoriteRepository** | getFavorite, listFavorites, isFavorited | markFavorite, unmarkFavorite, updateLastAccessed |
| **ImportBatchRepository** | getImportBatchById, listActiveImportBatches, listCompletedImportBatches, getImportBatchBySource | createImportBatch, completeImportBatch, deleteImportBatch |

---

## Error Codes (Standard)

All layers use these standard error codes:

```
NotFoundError       (404) - Entity not found
DuplicateError      (409) - Constraint violated (unique, etc.)
ValidationError     (422) - Data invalid (type, range, format)
ConstraintError     (422) - FK or check constraint
TransactionError    (500) - Atomic operation failed
StorageError        (503) - Database unavailable
ForbiddenError      (403) - Permission denied
```

---

## Casting Patterns (6 Cross-Layer Transformations)

| From | To | Layer Boundary | Pattern |
|------|----|----|---------|
| ComicUI | CreateComicRequest | Presentation → IPC | Extract relevant fields, serialize image to file |
| CreateComicRequest | Comic | IPC → Domain | Validate rules, normalize title, construct entity |
| Comic | ComicRow + ComicMetadataRow | Domain → Database | Flatten aggregate, validate schema |
| ComicRow + ComicMetadataRow | Comic | Database → Domain | Join rows, construct entity, validate invariants |
| Comic | Comic (proto) | Domain → IPC | Derive computed fields, select fields for transmission |
| Comic (proto) | ComicUI | IPC → Presentation | Deserialize, load additional UI state |

---

## Security Boundaries

### What Can Cross Each Boundary

| Boundary | ✅ Allowed | ❌ Not Allowed |
|----------|-----------|----------------|
| **Infrastructure ↔ Ports** | Domain entities, error codes, primitives (UUID, String, int) | Database rows, SQL, file paths, connection strings |
| **Ports ↔ Application** | Domain entities, request/response DTOs, error codes, events | Repository implementations, DB connections, file handles |
| **Application ↔ Domain** | Domain entities, business exceptions (as value types) | Repositories, database queries, I/O calls |
| **Application ↔ Presentation (IPC)** | Protobuf messages (serialized), HTTP status codes, error codes | Raw domain entities, database objects, file handles |
| **Presentation ↔ User** | UI models, events (user taps, scrolls), images | Business logic, database access, secrets |

---

## Encryption & Security

### Encryption Points

**At Rest** (Database):
- Sensitive SourceManifest fields encrypted with AES-256-GCM
- App-derived key from installation ID + secret

**In Transit** (IPC):
- TLS 1.3 for all network communication
- Protocol Buffers for serialization
- Message integrity verified via HMAC (optional)

**In Memory**:
- API keys cleared after use
- Auth tokens cleared on logout
- Reader positions cleared on app close

### Validation Points

**At Presentation**: User input sanitized (no XSS, SQL injection attempts)
**At Application**: Request fields validated (non-empty, valid IDs, business rules)
**At Ports**: Entity fields validated (types, ranges, constraints)
**At Infrastructure**: Database rows validated (schema matches)

---

## DiagnosticsEvent System

All 14 use cases emit structured events:

| Event Type | Severity | Purpose | Example Payload |
|-----------|----------|---------|-----------------|
| **comic.created** | info | Audit trail | comicId, title, sourceType |
| **comic.updated** | info | Change tracking | comicId, fieldsChanged |
| **comic.deleted** | warning | Deletion audit | comicId, chapterCount |
| **comic.imported** | info | Import tracking | importBatchId, pageCount, duration |
| **reader.position_changed** | info | Usage analytics | fromChapter, toChapter, directionForward |
| **favorite.marked** | info | User preference | comicId, title |
| **import.batch_completed** | info | Import summary | comicId, pageCount, duration |
| **system.error_unhandled** | critical | Exception tracking | errorType, correlationId |

---

## IPC Protocol (Protocol Buffers v3)

All Presentation ↔ Application communication via:

```protobuf
// Request wrapper
message RpcRequest {
  string correlation_id = 1;      // UUID v4 trace ID
  string timestamp = 2;           // ISO8601 UTC
  int32 protocol_version = 3;     // 1, 2, 3, ...
  bytes payload = 4;              // Specific message
  map<string, string> metadata = 5; // Client info
}

// Response wrapper
message RpcResponse {
  string correlation_id = 1;      // Echo
  bool success = 2;
  int32 status_code = 3;          // 200, 404, 409, 422, 500
  bytes payload = 4;              // Response message
  ErrorDetail error = 5;          // If failed
}
```

All messages typed, versioned, backward compatible.

---

## Testing Strategy (Per Layer)

| Layer | Test Type | Example |
|-------|-----------|---------|
| **Infrastructure** | Integration | Database connections, query execution, transaction rollback |
| **Ports** | Contract | Repository interface validates input/output, error mapping |
| **Domain** | Unit | Entity invariants, business rules, no I/O occurs |
| **Application** | Integration | Use case orchestration, repository calls, events emitted |
| **Presentation** | E2E | IPC serialization, UI rendering, user interactions |

---

## Deployment Architecture

### Runtime Components

1. **Presentation** (Flutter/Dart on mobile/web)
   - Minimal dependencies (protobuf client)
   - No business logic

2. **Application Runtime** (Rust, Go, Kotlin, or other)
   - Can run on: mobile native, web service, desktop daemon
   - Communicates via IPC (gRPC, HTTP, or local socket)

3. **Infrastructure**
   - SQLite on device (no network required)
   - Optional: Network sync to cloud (future phase)

### Scaling Points

- **Ports**: Cache repository results
- **Application**: Thread pool for concurrent use cases
- **Infrastructure**: Connection pooling, prepared statements

---

## Implementation Checklist

- [ ] **Database**: Create 9 tables with all constraints
- [ ] **Infrastructure**: Implement 8 repository classes
- [ ] **Ports**: Define repository interface contracts
- [ ] **Domain**: Implement 10 entity classes with invariants
- [ ] **Application**: Implement 14 use cases
- [ ] **IPC**: Generate protobuf stubs (Rust/Go/Kotlin)
- [ ] **Presentation**: Create UI models and bindings
- [ ] **Diagnostics**: Emit events from all use cases
- [ ] **Testing**: Unit, integration, E2E tests per layer
- [ ] **Error Handling**: Standard error codes + mapping
- [ ] **Security**: Validation, encryption, logging
- [ ] **Documentation**: API docs, class docs, examples

---

## Quick Reference: Key Numbers

| Metric | Value | Notes |
|--------|-------|-------|
| Entities | 10 | Core domain models |
| Database Tables | 9 | Relational schema |
| Repositories | 8 | Data access interfaces |
| Use Cases | 14 | Business workflows |
| Events | 20+ | DiagnosticsEvent types |
| Error Codes | 7 | Standard errors |
| IPC Message Types | 30+ | Request/Response pairs |
| Security Boundaries | 5 | Between layers |

---

## Next Steps (Language Selection)

This design is **language-agnostic**. Choose implementation:

### Option 1: Rust (Recommended)
- Async: Tokio
- Database: SQLx (compile-time SQL checking)
- IPC: Tonic (gRPC)
- Testing: Built-in `#[test]`

### Option 2: Go
- Async: goroutines + channels
- Database: sqlc + Go SQL drivers
- IPC: gRPC + protobuf
- Testing: Go test framework

### Option 3: Kotlin
- Async: Coroutines
- Database: Exposed ORM
- IPC: gRPC + protobuf
- Testing: JUnit + Mockk

### Option 4: TypeScript/Node
- Async: async/await
- Database: Prisma ORM
- IPC: tRPC or GraphQL
- Testing: Jest

**All options implement identical logic - only syntax and libraries differ.**

---

## Documentation Artifacts

All design documents stored in `docs/design/`:

```
docs/design/
  ├─ entities.md
  ├─ database-schema.md
  ├─ repository-interfaces.md
  ├─ use-cases.md
  ├─ diagnostics-events.md
  ├─ security-boundaries-layering.md
  ├─ ipc-protocol-api.md
  ├─ class-definitions-casting.md
  └─ SUMMARY.md (this file)
```

All design decisions documented. Ready for implementation in any language.

---

## References

- **Architecture Pattern**: Hexagonal (Ports & Adapters)
- **Database Pattern**: Relational (normalized, transactions)
- **IPC Protocol**: Protocol Buffers v3 (gRPC)
- **Event Sourcing**: DiagnosticsEvent for audit trail
- **Error Handling**: Result types (Either<T, Error>)
- **Concurrency**: Last-write-wins for reader position
- **Security**: Layers validate at boundaries, encryption at sensitive points

