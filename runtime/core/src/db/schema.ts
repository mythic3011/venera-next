export interface ComicsTable {
  id: string;
  normalized_title: string;
  origin_hint: string;
  created_at: string;
  updated_at: string;
}

export interface ComicMetadataTable {
  comic_id: string;
  title: string;
  description: string | null;
  cover_page_id: string | null;
  cover_storage_object_id: string | null;
  author_name: string | null;
  metadata_json: string | null;
  created_at: string;
  updated_at: string;
}

export interface ComicTitlesTable {
  id: string;
  comic_id: string;
  title: string;
  normalized_title: string;
  locale: string | null;
  source_platform_id: string | null;
  source_link_id: string | null;
  title_kind: string;
  created_at: string;
}

export interface ChaptersTable {
  id: string;
  comic_id: string;
  parent_chapter_id: string | null;
  chapter_kind: string;
  chapter_number: number;
  title: string | null;
  display_label: string | null;
  created_at: string;
  updated_at: string;
}

export interface PagesTable {
  id: string;
  chapter_id: string;
  page_index: number;
  storage_object_id: string | null;
  chapter_source_link_id: string | null;
  mime_type: string | null;
  width: number | null;
  height: number | null;
  checksum: string | null;
  created_at: string;
  updated_at: string;
}

export interface PageOrdersTable {
  id: string;
  chapter_id: string;
  order_key: string;
  order_type: string;
  is_active: number;
  page_count: number;
  created_at: string;
  updated_at: string;
}

export interface PageOrderItemsTable {
  id: string;
  page_order_id: string;
  page_id: string;
  sort_index: number;
  created_at: string;
}

export interface SourcePlatformsTable {
  id: string;
  canonical_key: string;
  display_name: string;
  kind: string;
  is_enabled: number;
  created_at: string;
  updated_at: string;
}

export interface SourceLinksTable {
  id: string;
  comic_id: string;
  source_platform_id: string;
  remote_work_id: string;
  remote_url: string | null;
  display_title: string | null;
  link_status: string;
  confidence: string;
  created_at: string;
  updated_at: string;
}

export interface ChapterSourceLinksTable {
  id: string;
  chapter_id: string;
  source_link_id: string;
  remote_chapter_id: string;
  remote_url: string | null;
  remote_label: string | null;
  link_status: string;
  created_at: string;
  updated_at: string;
}

export interface StorageBackendsTable {
  id: string;
  backend_key: string;
  display_name: string;
  backend_kind: string;
  config_json: string;
  secret_ref: string | null;
  is_enabled: number;
  created_at: string;
  updated_at: string;
}

export interface StorageObjectsTable {
  id: string;
  object_kind: string;
  content_hash: string | null;
  size_bytes: number | null;
  mime_type: string | null;
  created_at: string;
  updated_at: string;
}

export interface StoragePlacementsTable {
  id: string;
  storage_object_id: string;
  storage_backend_id: string;
  object_key: string;
  role: string;
  sync_status: string;
  last_verified_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface ReaderSessionsTable {
  id: string;
  comic_id: string;
  chapter_id: string;
  page_id: string | null;
  page_index: number;
  source_link_id: string | null;
  chapter_source_link_id: string | null;
  reader_mode: string;
  created_at: string;
  updated_at: string;
}

export interface DiagnosticsEventsTable {
  id: string;
  schema_version: string;
  timestamp: string;
  level: string;
  channel: string;
  event_name: string;
  correlation_id: string | null;
  boundary: string | null;
  action: string | null;
  authority: string | null;
  comic_id: string | null;
  source_platform_id: string | null;
  payload_json: string;
}

export interface OperationIdempotencyTable {
  operation_name: string;
  idempotency_key: string;
  input_hash: string;
  status: string;
  result_type: string | null;
  result_resource_id: string | null;
  result_json: string | null;
  result_schema_version: string | null;
  created_at: string;
  updated_at: string;
}

export interface CoreDatabaseSchema {
  comics: ComicsTable;
  comic_metadata: ComicMetadataTable;
  comic_titles: ComicTitlesTable;
  chapters: ChaptersTable;
  pages: PagesTable;
  page_orders: PageOrdersTable;
  page_order_items: PageOrderItemsTable;
  source_platforms: SourcePlatformsTable;
  source_links: SourceLinksTable;
  chapter_source_links: ChapterSourceLinksTable;
  storage_backends: StorageBackendsTable;
  storage_objects: StorageObjectsTable;
  storage_placements: StoragePlacementsTable;
  reader_sessions: ReaderSessionsTable;
  diagnostics_events: DiagnosticsEventsTable;
  operation_idempotency: OperationIdempotencyTable;
}
