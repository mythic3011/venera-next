# IPC Protocol & API Contracts

**Language-agnostic IPC (Inter-Process Communication) message schemas and API contracts.**

---

## Overview

Venera uses **Protocol Buffers v3** for type-safe, versioned IPC between Dart/Flutter frontend (Presentation) and Rust backend (Application).

All communication:
- Serialized as protobuf binary
- Transmitted over gRPC/HTTP2 (TLS 1.3)
- Versioned for backward compatibility
- Validated at both layers

---

## Message Structure

```protobuf
// Base request/response for all RPC calls

message RpcRequest {
  string correlation_id = 1;     // UUID v4, trace ID
  string timestamp = 2;           // ISO8601, UTC
  int32 protocol_version = 3;    // 1, 2, 3, ...
  bytes payload = 4;              // Specific message (serialized)
  map<string, string> metadata = 5; // User-Agent, client version, etc
}

message RpcResponse {
  string correlation_id = 1;     // Echo from request
  string timestamp = 2;           // Server timestamp
  bool success = 3;               // Operation succeeded?
  int32 status_code = 4;          // 200, 404, 409, 422, 500
  bytes payload = 5;              // Response message (serialized)
  ErrorDetail error = 6;          // If success=false
}

message ErrorDetail {
  string error_code = 1;          // Machine-readable: NOT_FOUND, DUPLICATE, VALIDATION_ERROR
  string message = 2;             // Human-readable: "Comic not found"
  string error_type = 3;          // Exception type: NotFoundError, DuplicateError
}
```

---

## Comic Management Messages

### CreateComicRequest / CreateComicResponse

```protobuf
message CreateComicRequest {
  string title = 1;               // Required, non-empty
  string description = 2;         // Optional
  string author_name = 3;         // Optional
  repeated string genre_tags = 4; // Optional, max 10 tags
}

message CreateComicResponse {
  Comic comic = 1;                // Newly created comic
  DiagnosticsEvent event = 2;     // Audit event
}

// Nested: Comic (used in multiple messages)
message Comic {
  string id = 1;                  // UUID v4
  string normalized_title = 2;    // Lowercase, no punctuation
  string title = 3;
  string description = 4;
  string author_name = 5;
  repeated string genre_tags = 6;
  string cover_local_path = 7;    // Optional file path
  int32 chapter_count = 8;        // Read-only
  int32 page_count = 9;           // Read-only
  bool is_favorited = 10;         // Read-only
  ReaderPosition reader_position = 11; // Read-only
  string created_at = 12;         // ISO8601 timestamp
  string updated_at = 13;         // ISO8601 timestamp
}
```

### GetComicRequest / GetComicResponse

```protobuf
message GetComicRequest {
  string comic_id = 1;            // Required, UUID v4
}

message GetComicResponse {
  Comic comic = 1;
  ReaderSession session = 2;      // Current position
}
```

### UpdateComicMetadataRequest / UpdateComicMetadataResponse

```protobuf
message UpdateComicMetadataRequest {
  string comic_id = 1;            // Required
  string title = 2;               // Optional (if provided, checked for duplicates)
  string description = 3;         // Optional
  string author_name = 4;         // Optional
  repeated string genre_tags = 5; // Optional (replaces all tags)
  string cover_local_path = 6;    // Optional
}

message UpdateComicMetadataResponse {
  Comic comic = 1;                // Updated comic
  repeated string fields_changed = 2; // Audit: which fields changed
  DiagnosticsEvent event = 3;
}
```

### DeleteComicRequest / DeleteComicResponse

```protobuf
message DeleteComicRequest {
  string comic_id = 1;            // Required
  bool confirm_deletion = 2;      // Must be true (safety check)
}

message DeleteComicResponse {
  bool success = 1;
  string deleted_comic_id = 2;    // Returned for confirmation
  DiagnosticsEvent event = 3;
}
```

### ListComicsRequest / ListComicsResponse

```protobuf
message ListComicsRequest {
  int32 limit = 1;                // Default 50, max 1000
  int32 offset = 2;               // Default 0 (pagination)
  string sort_by = 3;             // "title" | "created" | "updated" | "last_read"
  string sort_order = 4;          // "asc" | "desc"
}

message ListComicsResponse {
  repeated Comic comics = 1;
  int32 total_count = 2;          // Total comics (for pagination UI)
  int32 limit = 3;                // Echoed
  int32 offset = 4;               // Echoed
}
```

### SearchComicsRequest / SearchComicsResponse

```protobuf
message SearchComicsRequest {
  string query = 1;               // Required, search terms
  int32 limit = 2;                // Default 50
  int32 offset = 3;               // Default 0
}

message SearchComicsResponse {
  repeated Comic comics = 1;      // Ranked by relevance
  int32 total_matches = 2;
  string query = 3;               // Echoed
}
```

---

## Import Messages

### ImportComicRequest / ImportComicResponse

```protobuf
message ImportComicRequest {
  string source_type = 1;         // "cbz" | "pdf" | "directory"
  string source_path = 2;         // Absolute path (validated)
  ImportMetadata metadata = 3;    // Override title, author, genres
  string grouping_strategy = 4;   // "single_chapter" | "by_folder" | "by_file"
  string chapter_numbering = 5;   // "sequential" | "by_filename"
}

message ImportMetadata {
  string title = 1;               // Optional override
  string author_name = 2;         // Optional
  repeated string genre_tags = 3; // Optional
}

message ImportComicResponse {
  Comic comic = 1;                // Newly created or matched comic
  string import_batch_id = 2;     // UUID of import batch
  int32 pages_created = 3;        // Count of pages imported
  int32 chapters_created = 4;     // Count of chapters created
  DiagnosticsEvent event = 5;
}
```

### ImportBatchStatusRequest / ImportBatchStatusResponse

```protobuf
message ImportBatchStatusRequest {
  string import_batch_id = 1;
}

message ImportBatchStatusResponse {
  string status = 1;              // "in_progress" | "completed" | "failed"
  int32 pages_processed = 2;
  int32 pages_total = 3;
  string error_message = 4;       // If failed
}
```

---

## Reader Position Messages

### UpdateReaderPositionRequest / UpdateReaderPositionResponse

```protobuf
message UpdateReaderPositionRequest {
  string comic_id = 1;            // Required
  string chapter_id = 2;          // Required
  int32 page_index = 3;           // Required (0-based)
}

message UpdateReaderPositionResponse {
  ReaderSession session = 1;      // Updated position
  bool is_favorited = 2;          // If favorited, last_accessed_at updated
  DiagnosticsEvent event = 3;
}

message ReaderSession {
  string id = 1;                  // UUID v4
  string comic_id = 2;
  string chapter_id = 3;
  int32 page_index = 4;
  int32 active_tab_position = 5;  // Reserved
  string created_at = 6;
  string updated_at = 7;
}

message ReaderPosition {
  string chapter_id = 1;
  int32 page_index = 2;
}
```

### GetReaderPositionRequest / GetReaderPositionResponse

```protobuf
message GetReaderPositionRequest {
  string comic_id = 1;
}

message GetReaderPositionResponse {
  ReaderSession session = 1;      // Current position or default
  bool is_at_start = 2;           // Convenience flag
  bool is_at_end = 3;             // Convenience flag
}
```

### ClearReaderPositionRequest / ClearReaderPositionResponse

```protobuf
message ClearReaderPositionRequest {
  string comic_id = 1;
}

message ClearReaderPositionResponse {
  ReaderSession session = 1;      // Reset to start
  DiagnosticsEvent event = 2;
}
```

---

## Chapter & Page Messages

### ListChaptersRequest / ListChaptersResponse

```protobuf
message ListChaptersRequest {
  string comic_id = 1;            // Required
}

message ListChaptersResponse {
  repeated Chapter chapters = 1;  // Ordered by chapter_number
}

message Chapter {
  string id = 1;                  // UUID v4
  string comic_id = 2;
  float chapter_number = 3;       // e.g., 1.0, 1.5, 2.0
  string title = 4;               // Optional
  int32 page_count = 5;           // Read-only
  string created_at = 6;
  string updated_at = 7;
}
```

### ListPagesRequest / ListPagesResponse

```protobuf
message ListPagesRequest {
  string chapter_id = 1;          // Required
}

message ListPagesResponse {
  repeated Page pages = 1;        // Ordered by page_index
}

message Page {
  string id = 1;                  // UUID v4
  string chapter_id = 2;
  int32 page_index = 3;           // 0-based
  string local_cache_path = 4;    // Optional file path
  string created_at = 5;
  string updated_at = 6;
}
```

### ReorderPagesRequest / ReorderPagesResponse

```protobuf
message ReorderPagesRequest {
  string chapter_id = 1;
  repeated string page_ids = 2;   // New user-defined order
}

message ReorderPagesResponse {
  PageOrder page_order = 1;
  repeated string new_order = 2;  // Reordered page IDs
  DiagnosticsEvent event = 3;
}

message PageOrder {
  string id = 1;                  // UUID v4
  string chapter_id = 2;
  string order_type = 3;          // "source" | "user_override" | "import_detected"
  int32 page_count = 4;           // Informational
  string created_at = 5;
  string updated_at = 6;
}
```

---

## Favorite Messages

### MarkFavoriteRequest / MarkFavoriteResponse

```protobuf
message MarkFavoriteRequest {
  string comic_id = 1;
}

message MarkFavoriteResponse {
  Favorite favorite = 1;
  DiagnosticsEvent event = 2;
}

message Favorite {
  string id = 1;                  // UUID v4
  string comic_id = 2;
  string marked_at = 3;           // ISO8601, immutable
  string last_accessed_at = 4;    // ISO8601, nullable
}
```

### UnmarkFavoriteRequest / UnmarkFavoriteResponse

```protobuf
message UnmarkFavoriteRequest {
  string comic_id = 1;
}

message UnmarkFavoriteResponse {
  bool success = 1;
  string comic_id = 2;
  DiagnosticsEvent event = 3;
}
```

### ListFavoritesRequest / ListFavoritesResponse

```protobuf
message ListFavoritesRequest {
  int32 limit = 1;                // Default 100
  int32 offset = 2;               // Default 0
}

message ListFavoritesResponse {
  repeated FavoritedComic comics = 1;
  int32 total_count = 2;
}

message FavoritedComic {
  Favorite favorite = 1;
  Comic comic = 2;                // Full comic data
}
```

---

## Streaming Messages (Optional, for real-time updates)

### SubscribeToEventsRequest / EventStream

```protobuf
message SubscribeToEventsRequest {
  repeated string event_types = 1; // e.g., ["reader.position_changed", "favorite.marked"]
  string resource_id = 2;         // Optional, filter by resource
}

// Server streams these:
message EventMessage {
  DiagnosticsEvent event = 1;
  string timestamp = 2;
  int64 sequence_number = 3;      // For ordering
}
```

---

## Diagnostics Event Message

```protobuf
message DiagnosticsEvent {
  string id = 1;                  // UUID v4
  string timestamp = 2;           // ISO8601, UTC
  string correlation_id = 3;      // UUID v4, trace ID
  string session_id = 4;          // Optional
  string user_id = 5;             // Optional, hashed
  
  string event_type = 6;          // "comic.created", "reader.position_changed"
  string category = 7;            // "comic", "reader", "favorite", "source", "import", "system"
  string severity = 8;            // "info", "warning", "error", "critical"
  
  string resource_type = 9;       // "Comic", "Chapter", "Page", "ReaderSession"
  string resource_id = 10;        // UUID of affected resource
  string action = 11;             // "created", "updated", "deleted", "accessed"
  
  bytes payload = 12;             // JSON object (event-specific data)
  bytes metadata = 13;            // JSON object (context)
  
  int32 duration_ms = 14;         // Milliseconds
  bool success = 15;
  ErrorDetail error = 16;         // If failed
}
```

---

## Batch Operations

### BatchUpdateReaderPositionsRequest / BatchUpdateReaderPositionsResponse

```protobuf
message BatchUpdateReaderPositionsRequest {
  repeated ReaderPositionUpdate updates = 1;
}

message ReaderPositionUpdate {
  string comic_id = 1;
  string chapter_id = 2;
  int32 page_index = 3;
}

message BatchUpdateReaderPositionsResponse {
  int32 updated_count = 1;
  repeated string failed_comic_ids = 2;
  DiagnosticsEvent event = 3;
}
```

---

## Schema Validation

### At Presentation (Before sending)
```
1. All required fields populated
2. String lengths within limits (max 500 for titles)
3. IDs are valid UUID v4 format
4. Timestamps are ISO8601
5. Arrays have reasonable sizes (max 1000 items)
6. Enums match allowed values
```

### At Application (Upon receiving)
```
1. Protobuf message deserializes successfully
2. All required fields present
3. Timestamp not too old (anti-replay)
4. Correlation ID is valid UUID v4
5. Resources referenced (comic IDs) exist
6. Business rules satisfied (no duplicates, etc.)
```

---

## Error Response Examples

### 404 Not Found
```json
{
  "success": false,
  "status_code": 404,
  "error": {
    "error_code": "NOT_FOUND",
    "message": "Comic with id abc123 not found",
    "error_type": "NotFoundError"
  }
}
```

### 409 Duplicate
```json
{
  "success": false,
  "status_code": 409,
  "error": {
    "error_code": "DUPLICATE",
    "message": "Comic title 'My Comic' already exists",
    "error_type": "DuplicateError"
  }
}
```

### 422 Validation Error
```json
{
  "success": false,
  "status_code": 422,
  "error": {
    "error_code": "VALIDATION_ERROR",
    "message": "Title cannot be empty",
    "error_type": "ValidationError"
  }
}
```

### 500 Internal Error
```json
{
  "success": false,
  "status_code": 500,
  "error": {
    "error_code": "INTERNAL_ERROR",
    "message": "Database operation failed",
    "error_type": "StorageError"
  }
}
```

---

## Versioning Strategy

### Protocol Version Header
```
All requests include:
  protocol_version: 1

Server response:
  protocol_version: 2 (if upgrade needed)
  error_code: "PROTOCOL_UPGRADE_REQUIRED"
```

### Backward Compatibility
```
V1 message: CreateComicRequest { title, description }
V2 message: CreateComicRequest { title, description, author_name, genre_tags }

Server running V2 can handle V1 requests:
  - author_name defaults to null
  - genre_tags defaults to empty array
```

### Migration Strategy
```
1. Add new fields to proto with default values
2. Deploy server (V2) that handles both V1 and V2
3. Gradually update clients to V2
4. Once all clients V2, deprecate V1 handling
```

---

## Implementation Examples

### Dart/Flutter Presentation Layer (Pseudocode)
```dart
class RpcClient {
  Future<CreateComicResponse> createComic(String title) async {
    final request = CreateComicRequest()
      ..title = title
      ..description = "Imported comic";
    
    final rpcRequest = RpcRequest()
      ..correlationId = uuid.v4()
      ..timestamp = DateTime.now().toIso8601String()
      ..protocolVersion = 1
      ..payload = request.writeToBuffer();
    
    // Send via gRPC
    final response = await client.sendRequest(rpcRequest);
    
    if (response.success) {
      return CreateComicResponse.fromBuffer(response.payload);
    } else {
      throw Exception("Failed: ${response.error.message}");
    }
  }
}
```

### Rust Application Layer (Pseudocode)
```rust
pub async fn create_comic(
    req: CreateComicRequest,
    repo: &ComicRepository,
) -> Result<CreateComicResponse, RpcError> {
    // Validate input
    if req.title.is_empty() {
        return Err(RpcError::validation("title_required"));
    }
    
    // Execute use case
    let comic = repo.create_comic(&req.title, &req.description)?;
    
    // Emit event
    emit_event(DiagnosticsEvent {
        event_type: "comic.created",
        resource_id: comic.id.clone(),
        payload: serde_json::json!({ "title": &comic.title }),
        ..Default::default()
    });
    
    Ok(CreateComicResponse {
        comic: Some(comic.to_proto()),
        ..Default::default()
    })
}
```

---

## Rate Limiting & Throttling

```
All endpoints enforce:
  - Max 1000 requests per minute per session
  - Max 100 MB upload per file
  - Max 10 parallel imports
  
Exceeded: Return HTTP 429 (Too Many Requests)
  Retry-After: 60 (seconds)
```

---

## Security: No Secrets in IPC

```
✓ ALLOWED:
  - Source manifest endpoint: "https://api.copymanga.com/search"
  - Comic ID: "550e8400-e29b-41d4-a716-446655440000"

✗ NOT ALLOWED:
  - API key: "sk_live_abc123xyz789"
  - Database connection string: "postgresql://user:pass@host/db"
  - Auth token: "Bearer eyJhbGc..."
```

All secrets are managed server-side only.

