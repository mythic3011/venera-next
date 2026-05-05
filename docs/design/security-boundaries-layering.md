# Security Boundaries & Layering Specification

**Language-agnostic layering architecture with security boundaries, entity definitions, and API contracts.**

---

## Overview

Venera's canonical runtime uses **5-layer hexagonal architecture** with explicit security boundaries between layers. Each layer has:
- **Owned entities** (models living in this layer)
- **Interface contracts** (APIs to dependencies)
- **Security boundary** (validation, transformation, encryption)
- **Responsibility** (what this layer does)
- **Cannot depend on** (what it doesn't call)

---

## Layer Stack (Bottom-Up)

```
┌─────────────────────────────────────┐
│  Presentation (Flutter/Dart)        │ External API (IPC)
├─────────────────────────────────────┤
│  Application (Use Cases)            │ Business logic orchestration
├─────────────────────────────────────┤ ⬅️ Security Boundary
│  Domain (Entities & Rules)          │ Pure business models, no I/O
├─────────────────────────────────────┤ ⬅️ Security Boundary
│  Ports (Repository Interfaces)      │ Abstraction over persistence
├─────────────────────────────────────┤ ⬅️ Security Boundary
│  Infrastructure (DB, File I/O)      │ SQLite, file system, network
└─────────────────────────────────────┘
```

---

## Layer 1: Infrastructure

**Responsibility**: Lowest level I/O (database, filesystem, network adapters).

### Owned Entities
None. Infrastructure works with **database rows** (not business entities).

### API Contracts (Depends On: Nothing)

#### DatabaseConnection
```
trait DatabaseConnection:
  execute(sql: String, params: Array) -> QueryResult
  beginTransaction() -> Transaction
  rollback()
  commit()
```

#### FileSystemAdapter
```
trait FileSystemAdapter:
  readFile(path: String) -> Buffer
  writeFile(path: String, data: Buffer)
  listDirectory(path: String) -> List<String>
  delete(path: String) -> Boolean
  exists(path: String) -> Boolean
```

#### HttpClient
```
trait HttpClient:
  get(url: String, headers: Map) -> Response
  post(url: String, body: String, headers: Map) -> Response
  setTimeout(ms: Integer)
```

### Security Boundaries
- **Input validation**: URL validation, file path validation (no directory traversal)
- **Output sanitization**: No secrets in logs, no exceptions expose internals
- **Access control**: File I/O only to app directories
- **Encryption**: TLS for HTTP, encrypted storage for sensitive files

### Implementation Details
```
Infrastructure Layer:
  database/
    connection.rs
    schema.rs
    migrations/
  filesystem/
    adapter.rs
    cache.rs
  http/
    client.rs
    retry_policy.rs
  encryption/
    aes_256_gcm.rs
    key_derivation.rs
```

### Logging Strategy
```
[INFRASTRUCTURE] Database query: SELECT * FROM comics (duration: 45ms)
[INFRASTRUCTURE] File written: /cache/cover_abc123.jpg (1.2MB)
[INFRASTRUCTURE] HTTP GET: https://copymanga.com/api/search (status: 200, 1230ms)
```

**Never log**: Connection strings, API keys, file contents, exceptions details

---

## Layer 2: Ports (Repository Interfaces)

**Responsibility**: Abstract data access patterns. Repository interfaces are **defined here**, implementations are in Infrastructure.

### Owned Entities
None. Ports define **interfaces**, not implementations.

### API Contracts (Depends On: Infrastructure)

Each repository interface specifies:
- **Input types** (from Domain layer)
- **Output types** (from Domain layer)
- **Error codes** (domain-specific errors, not DB errors)

#### ComicRepository (Interface)
```
trait ComicRepository:
  interface Query:
    getComicById(id: ComicId) -> Comic | Error
    getComicByNormalizedTitle(title: String) -> Comic | Error
    listAllComics(limit, offset) -> List<Comic>
  
  interface Command:
    createComic(title: String, description: String) -> Comic | Error
    updateComicMetadata(id: ComicId, metadata: ComicMetadata) -> Comic | Error
    deleteComic(id: ComicId) -> Boolean | Error
```

#### ChapterRepository (Interface)
```
trait ChapterRepository:
  interface Query:
    getChapterById(id: ChapterId) -> Chapter | Error
    listChaptersByComic(comicId: ComicId) -> List<Chapter>
    getChapterByNumber(comicId: ComicId, num: Float) -> Chapter | Error
  
  interface Command:
    createChapter(comicId: ComicId, number: Float, title: String) -> Chapter | Error
    deleteChapter(id: ChapterId) -> Boolean | Error
```

**See**: `docs/design/repository-interfaces.md` for full specification.

### Security Boundaries
- **Input validation**: Check all parameters (type, range, constraints) before delegating to Infrastructure
- **Output validation**: Ensure returned entities match schema before returning to Application
- **Error transformation**: Convert infrastructure errors (SQL, I/O) to domain errors
- **No cascading exceptions**: All exceptions caught, logged, transformed

### Implementation Pattern
```
# ComicRepository Interface (Ports layer)
trait ComicRepository:
  getComicById(id: ComicId) -> Comic | NotFoundError

# ComicRepository Implementation (Infrastructure layer)
class SqliteComicRepository implements ComicRepository:
  constructor(db: DatabaseConnection, logger: Logger)
  
  getComicById(id: ComicId) -> Comic | Error:
    # Step 1: Validate input
    if id == null:
      throw ValidationError("id required")
    
    # Step 2: Query database
    row = db.execute(
      "SELECT * FROM comics WHERE id = ?",
      [id]
    )
    
    # Step 3: Transform row to entity
    if row == null:
      log("Comic not found: ${id}")
      throw NotFoundError("Comic with id ${id} not found")
    
    comic = Comic.fromDatabaseRow(row)
    
    # Step 4: Return entity (Ports layer type)
    return comic
```

### Logging Strategy
```
[PORTS] ComicRepository.getComicById(id: abc123) -> Found
[PORTS] ComicRepository.createComic(title: "My Comic") -> Created with id def456
[PORTS] ComicRepository.getComicById(id: xyz789) -> NotFoundError
```

---

## Layer 3: Domain

**Responsibility**: Pure business logic, entities, rules, no I/O.

### Owned Entities (Core Models)

All entities defined in `docs/design/entities.md`:

#### Comic
```
Entity: Comic
  id: ComicId (UUID v4)
  normalizedTitle: String
  metadata: ComicMetadata (optional)
  favorite: Favorite (optional)
  readerSession: ReaderSession (optional)
  createdAt: Timestamp
  updatedAt: Timestamp
  
  Invariants:
    - id is immutable UUID v4
    - normalizedTitle is unique
    - normalizedTitle is lowercase, no punctuation
    - updatedAt >= createdAt
```

#### Chapter
```
Entity: Chapter
  id: ChapterId (UUID v4)
  comicId: ComicId (immutable)
  chapterNumber: Float (unique within comic, > 0)
  title: String (optional)
  pages: List<Page> (mutable, ordered)
  pageOrder: PageOrder (policy for reordering)
  createdAt: Timestamp
  updatedAt: Timestamp
  
  Invariants:
    - id is immutable
    - comicId is immutable
    - chapterNumber is unique within comic
    - pages are ordered by pageIndex 0..N
```

#### Page
```
Entity: Page
  id: PageId (UUID v4)
  chapterId: ChapterId (immutable)
  pageIndex: Integer (0-based, unique within chapter, contiguous)
  localCachePath: String (optional, file path)
  createdAt: Timestamp
  updatedAt: Timestamp
  
  Invariants:
    - id is immutable
    - chapterId is immutable
    - pageIndex is 0-based
    - pageIndex is contiguous (no gaps)
```

**See**: `docs/design/entities.md` for full entity definitions.

### Business Rules (Encapsulated in Entities)

#### Rule: Chapter Number Must Be Unique
```
class Chapter:
  function validateChapterNumber(comicId, number, existingChapters):
    for chapter in existingChapters:
      if chapter.chapterNumber == number:
        throw DuplicateError("Chapter ${number} exists in comic")
```

#### Rule: Page Index Must Be Contiguous
```
class Chapter:
  function validatePageIndices(pages):
    indices = pages.map(p => p.pageIndex).sort()
    for i in 0..indices.length-1:
      if indices[i] != i:
        throw ValidationError("Pages not contiguous: ${indices}")
```

#### Rule: Reader Position Must Be Valid
```
class ReaderSession:
  function validatePosition(comicId, chapterId, pageIndex, comic):
    chapter = comic.chapters.find(c => c.id == chapterId)
    if chapter == null:
      throw ValidationError("Chapter not in comic")
    if pageIndex >= chapter.pages.length:
      throw ValidationError("Page index out of bounds")
```

### API Contracts (Depends On: None)

Domain entities expose **only immutable interfaces**:
```
trait Comic:
  getId() -> ComicId (read-only)
  getNormalizedTitle() -> String (read-only)
  getMetadata() -> ComicMetadata (read-only)
  getChapters() -> List<Chapter> (read-only)
  getReaderSession() -> ReaderSession (read-only)
  validate() -> ValidationResult (check invariants)
```

### Security Boundaries
- **No I/O in domain**: Domain never calls databases, files, or network
- **No exceptions cross layers**: Domain exceptions are value types (ValidationError contains code + message)
- **Pure functions only**: Same input = same output, no side effects
- **Immutable aggregates**: Entities can't be modified after creation (if mutable, changes tracked via events)

### Logging Strategy
```
[DOMAIN] Comic created: Comic(id=abc123, title="My Comic")
[DOMAIN] Chapter added: Chapter 1.0 with 25 pages
[DOMAIN] Reader position: Chapter 2, Page 10 (valid)
[DOMAIN] Validation failed: Chapter number 2.0 already exists
```

**Never log**: Full entity state (too verbose), internal field values

---

## Layer 4: Application (Use Cases)

**Responsibility**: Orchestrate repositories + domain rules to implement use cases.

### Owned Entities
None. Application uses **Domain entities** and emits **DiagnosticsEvents**.

### API Contracts (Depends On: Domain + Ports)

Each use case has:
- **Input** (request object from Presentation)
- **Output** (response object to Presentation)
- **Errors** (domain error codes)
- **Events** (diagnostics events emitted)

#### UseCase: CreateComicUseCase
```
trait CreateComicUseCase:
  function execute(request: CreateComicRequest) -> CreateComicResponse | Error:
    
    Input:
      {
        title: String (non-empty)
        description: String (optional)
        authorName: String (optional)
        genreTags: List<String> (optional)
      }
    
    Output:
      {
        comic: Comic (with assigned ID)
        event: DiagnosticsEvent (type: "comic.created")
      }
    
    Errors:
      - DuplicateError (title already exists)
      - ValidationError (title empty)
      - StorageError (database fails)
```

#### UseCase: ImportComicUseCase
```
trait ImportComicUseCase:
  function execute(request: ImportComicRequest) -> ImportComicResponse | Error:
    
    Input:
      {
        sourceType: String ("cbz" | "pdf" | "directory")
        sourcePath: String
        importMetadata: Object (title, author, genres)
      }
    
    Output:
      {
        comic: Comic
        importBatch: ImportBatch
        pagesCreated: Integer
        event: DiagnosticsEvent (type: "comic.imported")
      }
    
    Errors:
      - NotFoundError (file not found)
      - ValidationError (not valid images)
      - DuplicateError (same file already importing)
```

**See**: `docs/design/use-cases.md` for full use case specifications.

### Business Logic Orchestration

```
function CreateComicUseCase.execute(request):
  # Step 1: Input validation (Application responsibility)
  if request.title.isEmpty():
    emit DiagnosticsEvent(type: "validation.failed", severity: "warning")
    throw ValidationError("title_required")
  
  # Step 2: Domain rule check (Domain responsibility)
  normalizedTitle = normalizeTitle(request.title)
  
  # Step 3: Query repository (Ports responsibility)
  existingComic = comicRepository.getComicByNormalizedTitle(normalizedTitle)
  if existingComic != null:
    emit DiagnosticsEvent(type: "validation.failed", severity: "warning")
    throw DuplicateError("comic_title_exists", title: request.title)
  
  # Step 4: Create domain entity (Domain responsibility)
  comic = Comic.create(
    title: request.title,
    normalizedTitle: normalizedTitle,
    description: request.description
  )
  
  # Step 5: Persist via repository (Ports responsibility)
  savedComic = comicRepository.createComic(comic)
  
  # Step 6: Initialize related entities
  readerSession = readerSessionRepository.createSession(savedComic.id)
  
  # Step 7: Emit event for audit trail
  emit DiagnosticsEvent(
    type: "comic.created",
    resourceId: savedComic.id,
    payload: { title: savedComic.title }
  )
  
  # Step 8: Return response (mapped to Presentation layer)
  return CreateComicResponse(
    comic: savedComic,
    success: true
  )
```

### Security Boundaries
- **Request validation**: Sanitize all inputs before passing to domain/repositories
- **Authorization**: Check permissions before executing use case
- **Output encryption**: Encrypt sensitive fields if needed before returning
- **Audit trail**: Every use case emits DiagnosticsEvent
- **Error handling**: Catch all exceptions, transform to standard error codes

### Logging Strategy
```
[APPLICATION] UseCase: CreateComic started (correlationId: req123)
[APPLICATION] Input validated: title="My Comic", description present
[APPLICATION] Domain rule check: normalized title unique
[APPLICATION] Repository call: comicRepository.createComic()
[APPLICATION] Comic created with id: abc123
[APPLICATION] Event emitted: comic.created
[APPLICATION] UseCase: CreateComic completed (duration: 234ms)
```

---

## Layer 5: Presentation (Flutter/Dart + IPC)

**Responsibility**: User interface, IPC communication with runtime, event handling.

### Owned Entities

#### PresentationModel (UI-specific, not business entity)
```
class ComicListViewModel:
  comics: List<ComicUI>
  isLoading: Boolean
  error: String
  
  function loadComics():
    isLoading = true
    comics = runtimeClient.listComics()
    isLoading = false
  
  function onComicTap(comicId):
    runtimeClient.updateReaderPosition(comicId, chapter: 0, page: 0)
    navigate(ReaderScreen, comic: comicId)
```

### API Contracts (IPC to Application)

All communication via **Protocol Buffers** with type-safe serialization:

#### Proto: CreateComicRequest
```protobuf
message CreateComicRequest {
  string correlation_id = 1;
  string title = 2;
  string description = 3;
  string author_name = 4;
  repeated string genre_tags = 5;
}

message CreateComicResponse {
  bool success = 1;
  Comic comic = 2;
  string error_code = 3;
}
```

#### Proto: ReaderPositionEvent
```protobuf
message ReaderPositionEvent {
  string correlation_id = 1;
  string comic_id = 2;
  string chapter_id = 3;
  int32 page_index = 4;
  int64 timestamp_ms = 5;
}
```

### Security Boundaries
- **IPC validation**: All messages validated against protobuf schema
- **Untrusted input**: User input sanitized before sending to runtime
- **Response mapping**: Runtime responses mapped to UI models (never expose raw domain entities)
- **Error handling**: Runtime errors translated to user-friendly messages
- **No business logic**: All decisions delegated to runtime (Application + Domain layers)

### Logging Strategy
```
[PRESENTATION] User tapped: ComicDetail(id: abc123)
[PRESENTATION] IPC sent: GetComicRequest(id: abc123)
[PRESENTATION] IPC received: GetComicResponse(title: "My Comic", chapters: 12)
[PRESENTATION] Navigation: ReaderScreen opened
[PRESENTATION] Error: Network timeout (retrying in 3s)
```

---

## Cross-Layer Communication

### Presentation → Application (IPC)
```
Presentation sends: ProtocolBuffer (serialized)
Application receives: Message deserialized, validated
Application executes: UseCase.execute(request)
Application returns: Response + Event
Presentation receives: ProtocolBuffer (response)
Presentation renders: UI updated
```

**Schema**: All IPC messages in `schemas/ipc-*.proto`

### Application → Ports → Infrastructure
```
Application calls: Repository.query(params)
Ports validates: Input parameters type-checked
Infrastructure executes: Database query
Infrastructure returns: Database row
Ports transforms: Row → Domain entity
Ports validates: Entity matches schema
Application receives: Strongly-typed entity
```

### Domain (Pure Business Logic)
```
Application creates: Domain entity
Domain validates: Invariants checked
Domain returns: Validation result
Application uses: Validation result to decide
```

---

## Entity Lifecycle

### Creation Flow
```
[PRESENTATION] User input
    ↓ (IPC Message)
[APPLICATION] CreateComicUseCase.execute()
    ↓ (Domain entity)
[DOMAIN] Comic.create() - validate rules
    ↓ (Comic instance)
[APPLICATION] comicRepository.createComic()
    ↓ (Ports interface)
[INFRASTRUCTURE] SqliteComicRepository.createComic()
    ↓ (SQL INSERT)
[DATABASE] Row created
    ↓ (Row returned)
[INFRASTRUCTURE] Transform row → Comic
    ↓ (Comic instance)
[PORTS] Validate entity
    ↓ (Comic instance)
[APPLICATION] Emit event
    ↓ (DiagnosticsEvent)
[PRESENTATION] Render UI
```

### Update Flow
```
[PRESENTATION] User edit metadata
    ↓ (IPC Message)
[APPLICATION] UpdateComicMetadataUseCase.execute()
    ↓ (Validate new title not duplicate)
[DOMAIN] Validate rules
    ↓ (Validation passed)
[APPLICATION] comicRepository.updateComicMetadata()
    ↓ (Ports interface)
[INFRASTRUCTURE] SqliteComicRepository.updateComicMetadata()
    ↓ (SQL UPDATE)
[DATABASE] Row updated
    ↓ (Row returned)
[INFRASTRUCTURE] Transform row → Comic
    ↓ (Comic instance)
[APPLICATION] Emit event
    ↓ (DiagnosticsEvent)
[PRESENTATION] UI re-rendered
```

### Query Flow
```
[PRESENTATION] User navigates to comics list
    ↓ (IPC Message: ListComicsRequest)
[APPLICATION] ListComicsUseCase.execute()
    ↓ (Pagination: limit=50, offset=0)
[APPLICATION] comicRepository.listAllComics(50, 0)
    ↓ (Ports interface)
[INFRASTRUCTURE] SqliteComicRepository.listAllComics()
    ↓ (SQL SELECT with pagination)
[DATABASE] Rows returned
    ↓ (Rows list)
[INFRASTRUCTURE] Transform rows → List<Comic>
    ↓ (List<Comic>)
[PORTS] Validate each entity
    ↓ (List<Comic>)
[APPLICATION] Emit event (optional)
    ↓ (List<Comic>)
[PRESENTATION] Render comics grid
```

---

## Security Boundaries Enforcement

### Boundary 1: Infrastructure ↔ Ports

**What can cross**:
- Domain entities (Comic, Chapter, Page)
- Standard error codes (NotFoundError, ValidationError)
- Primitives (UUID, String, Integer, Timestamp)

**What cannot cross**:
- Database rows (implementation detail)
- SQL queries
- File system paths
- HTTP URLs
- Connection strings
- API keys

**Enforcement**:
```
# ALLOWED
function getComicById(id: ComicId) -> Comic:
  return repository.getComicById(id)  # Returns Comic entity

# FORBIDDEN
function getComicById(id: ComicId) -> Map:
  return database.query("SELECT * FROM comics WHERE id = ?", [id])  # Raw row
```

### Boundary 2: Ports ↔ Application

**What can cross**:
- Domain entities (Comic, Chapter, Page)
- Request objects (CreateComicRequest, UpdateComicRequest)
- Response objects (CreateComicResponse)
- Standard error codes
- DiagnosticsEvents

**What cannot cross**:
- Repository implementations
- Database connections
- File handles
- HTTP clients

**Enforcement**:
```
# ALLOWED
function createComic(request: CreateComicRequest) -> Comic:
  comic = comicRepository.createComic(request.title)
  return comic

# FORBIDDEN
function createComic(request: CreateComicRequest):
  db.execute("INSERT INTO comics ...")  # Direct DB access
```

### Boundary 3: Application ↔ Domain

**What can cross**:
- Domain entities
- Domain rules (validation results)
- Business exceptions (DuplicateError with message)

**What cannot cross**:
- Database queries
- File I/O
- Network calls
- Repositories

**Enforcement**:
```
# ALLOWED (Domain returns value type)
result = validateComicTitle(title)  # Returns ValidationError or null

# FORBIDDEN (Domain does I/O)
chapter = database.query("SELECT * FROM chapters WHERE id = ?")
```

### Boundary 4: Application ↔ Presentation (IPC)

**What can cross**:
- Protocol Buffer messages (serialized)
- JSON (for simple cases)
- Standard HTTP status codes
- Error codes (domain errors mapped to HTTP)

**What cannot cross**:
- Raw domain entities (must be serialized)
- Database objects
- File handles
- Presentation models directly

**Enforcement**:
```
# ALLOWED (Serialized)
message CreateComicResponse {
  Comic comic = 1;  # Serialized via proto
  string error = 2;
}

# FORBIDDEN (Direct reference)
class ComicUI extends Comic:  # Bad - mixing layers
```

---

## Schema Validation Points

### At Infrastructure
```
[Input] Raw database row
  ↓ (Validate against table schema)
[Check] All columns present, types correct
  ↓ (Transform)
[Output] Domain entity
```

### At Ports
```
[Input] Domain entity from Application
  ↓ (Validate against entity schema)
[Check] All fields valid, invariants hold
  ↓ (Transform to database row)
[Output] Database INSERT/UPDATE
```

### At Application
```
[Input] Request from Presentation (IPC)
  ↓ (Validate against proto schema + business rules)
[Check] Title not empty, title not duplicate, author valid
  ↓ (Construct domain entity)
[Output] Domain entity to Ports
```

### At Presentation
```
[Input] Response from Application (IPC)
  ↓ (Validate against proto schema)
[Check] Message well-formed, required fields present
  ↓ (Map to UI model)
[Output] ComicUI for rendering
```

---

## Encryption & Security

### Encryption Points

#### At Rest (Database)
```
Sensitive fields:
  - User passwords (hash with bcrypt, never encrypt)
  - API keys in SourceManifest (encrypt with app key)
  - Cached images (no encryption, files already on device)

Implementation:
  [Field] SourceManifest.baseUrl
  [Encrypt] AES-256-GCM with app-derived key
  [Store] Encrypted blob in database
  [Retrieve] Decrypt on read, validate integrity
```

#### In Transit (IPC)
```
All IPC communication:
  - TLS 1.3 for network transport
  - Protocol Buffers for serialization
  - Message integrity verified

Implementation:
  [Serialize] CreateComicRequest → protobuf bytes
  [Encrypt] gRPC/TLS tunnel
  [Deserialize] protobuf bytes → message
  [Validate] Message signature + timestamp
```

#### In Memory
```
Sensitive data:
  - API keys (clear after use)
  - User auth tokens (cleared on logout)
  - Reader positions (cleared on app close)

Implementation:
  [Create] Entity with sensitive field
  [Use] Immediately in business logic
  [Clear] Overwrite memory after use
```

### Security Validation

#### Input Validation (At each layer)
```
[Infrastructure] File paths - no directory traversal
[Infrastructure] URLs - must be HTTPS, known hosts
[Infrastructure] SQL queries - parameterized (no injection)
[Ports] Entity fields - type checked, range validated
[Application] Request fields - non-empty strings, valid IDs
[Presentation] User input - XSS prevention, sanitization
```

#### Output Validation
```
[Infrastructure] Rows from database - validate schema
[Ports] Entities returned - validate invariants
[Application] Responses - validate required fields
[Presentation] IPC messages - validate protobuf schema
```

---

## Layer Responsibilities Summary

| Layer | Responsibility | Owns | Depends On | Cannot Do |
|-------|---|---|---|---|
| **Presentation** | UI rendering, IPC | Models, Events | Application | Business logic, persistence |
| **Application** | Use case orchestration | None (uses Domain + Ports) | Domain, Ports | I/O directly |
| **Domain** | Pure business rules | Entities, Aggregates | None | I/O, databases, network |
| **Ports** | Repository interfaces | Interfaces only | Domain | I/O (implement in Infrastructure) |
| **Infrastructure** | Database, files, network | Implementations | Ports | Business logic |

---

## Testing Strategy Per Layer

### Infrastructure Tests
```
Test database operations:
  - Connection pooling
  - Query execution
  - Error handling
  - Transaction rollback
```

### Ports Tests
```
Test repository contracts:
  - Input validation
  - Output transformation
  - Error mapping
  - No raw rows returned
```

### Domain Tests
```
Test entity invariants:
  - Invalid IDs rejected
  - Duplicate values caught
  - Business rules enforced
  - No I/O occurs
```

### Application Tests
```
Test use cases:
  - Input validation
  - Repository calls correct
  - Events emitted
  - Errors handled
```

### Presentation Tests
```
Test UI:
  - IPC messages serialized correctly
  - Responses rendered
  - Errors displayed
  - User interactions trigger use cases
```

---

## Deployment Implications

### Versioning
- **Infrastructure**: Can change DB schema (backward compatible migrations)
- **Ports**: Can change repository interfaces (must update Infrastructure)
- **Domain**: Entity changes require careful migration (public API)
- **Application**: Use case changes may need UI updates
- **Presentation**: IPC changes require protocol version bump

### Scaling
- **Infrastructure**: Scale database connections, caching
- **Ports**: Cache repository results
- **Domain**: No scaling needed (pure logic)
- **Application**: Scale use case execution (thread pool)
- **Presentation**: Scale IPC handling (connection pool)

