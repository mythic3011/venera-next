import type {
  AddComicTitleInput,
  Comic,
  ComicMetadata,
  ComicTitle,
  CreateComicInput,
  CreateComicMetadataInput,
  NormalizedTitle,
} from "../domain/comic.js";
import type { Chapter, ChapterTreeNode, ListChapterChildrenInput } from "../domain/chapter.js";
import type { DiagnosticsEvent, DiagnosticsQuery, RecordDiagnosticsEventInput } from "../domain/diagnostics.js";
import type {
  ChapterId,
  ComicId,
  ComicTitleId,
  PageId,
  SourceLinkId,
  SourcePlatformId,
  StorageObjectId,
} from "../domain/identifiers.js";
import type {
  Page,
  PageOrderWithItems,
  SetUserPageOrderInput,
} from "../domain/page.js";
import type {
  ReaderSession,
  ReaderSessionPersistResult,
  UpdateReaderPositionInput,
} from "../domain/reader.js";
import type { ChapterSourceLink, ProviderWorkRef, SourceLink, SourcePlatform } from "../domain/source.js";
import type { StorageObject, StoragePlacement } from "../domain/storage.js";
import type { Result } from "../shared/result.js";

export interface ComicRepositoryPort {
  getById(id: ComicId): Promise<Result<Comic | null>>;
  getByNormalizedTitle(title: NormalizedTitle): Promise<Result<Comic | null>>;
  create(input: CreateComicInput): Promise<Result<Comic>>;
}

export interface ComicMetadataRepositoryPort {
  getByComicId(comicId: ComicId): Promise<Result<ComicMetadata | null>>;
  create(input: CreateComicMetadataInput): Promise<Result<ComicMetadata>>;
  update(input: CreateComicMetadataInput): Promise<Result<ComicMetadata>>;
}

export interface ComicTitleRepositoryPort {
  listByComic(comicId: ComicId): Promise<Result<readonly ComicTitle[]>>;
  addTitle(input: AddComicTitleInput): Promise<Result<ComicTitle>>;
  removeTitle(id: ComicTitleId): Promise<Result<void>>;
}

export interface ChapterRepositoryPort {
  getById(id: ChapterId): Promise<Result<Chapter | null>>;
  listTreeByComic(comicId: ComicId): Promise<Result<readonly ChapterTreeNode[]>>;
  listChildren(input: ListChapterChildrenInput): Promise<Result<readonly Chapter[]>>;
  listByComic(comicId: ComicId): Promise<Result<readonly Chapter[]>>;
}

export interface PageRepositoryPort {
  getById(id: PageId): Promise<Result<Page | null>>;
  listByChapter(chapterId: ChapterId): Promise<Result<readonly Page[]>>;
}

export interface PageOrderRepositoryPort {
  getActiveOrder(chapterId: ChapterId): Promise<Result<PageOrderWithItems | null>>;
  setUserOrder(input: SetUserPageOrderInput): Promise<Result<PageOrderWithItems>>;
  resetToSourceOrder(chapterId: ChapterId): Promise<Result<PageOrderWithItems>>;
}

export interface ReaderSessionRepositoryPort {
  getByComic(comicId: ComicId): Promise<Result<ReaderSession | null>>;
  upsertPosition(
    input: UpdateReaderPositionInput,
  ): Promise<Result<ReaderSessionPersistResult>>;
  clear(comicId: ComicId): Promise<Result<void>>;
}

export interface SourcePlatformRepositoryPort {
  getById(id: SourcePlatformId): Promise<Result<SourcePlatform | null>>;
  getByKey(canonicalKey: string): Promise<Result<SourcePlatform | null>>;
  listEnabled(): Promise<Result<readonly SourcePlatform[]>>;
}

export interface SourceLinkRepositoryPort {
  getById(id: SourceLinkId): Promise<Result<SourceLink | null>>;
  listByComic(comicId: ComicId): Promise<Result<readonly SourceLink[]>>;
  findByProviderWork(input: ProviderWorkRef): Promise<Result<SourceLink | null>>;
}

export interface ChapterSourceLinkRepositoryPort {
  listByChapter(chapterId: ChapterId): Promise<Result<readonly ChapterSourceLink[]>>;
  listBySourceLink(
    sourceLinkId: SourceLinkId,
  ): Promise<Result<readonly ChapterSourceLink[]>>;
}

export interface StorageObjectRepositoryPort {
  getObject(id: StorageObjectId): Promise<Result<StorageObject | null>>;
}

export interface StoragePlacementRepositoryPort {
  listPlacements(
    storageObjectId: StorageObjectId,
  ): Promise<Result<readonly StoragePlacement[]>>;
}

export interface DiagnosticsEventRepositoryPort {
  record(input: RecordDiagnosticsEventInput): Promise<Result<DiagnosticsEvent>>;
  query(input: DiagnosticsQuery): Promise<Result<readonly DiagnosticsEvent[]>>;
}

export interface CoreRepositories {
  readonly comics: ComicRepositoryPort;
  readonly comicMetadata: ComicMetadataRepositoryPort;
  readonly comicTitles: ComicTitleRepositoryPort;
  readonly chapters: ChapterRepositoryPort;
  readonly pages: PageRepositoryPort;
  readonly pageOrders: PageOrderRepositoryPort;
  readonly readerSessions: ReaderSessionRepositoryPort;
  readonly sourcePlatforms: SourcePlatformRepositoryPort;
  readonly sourceLinks: SourceLinkRepositoryPort;
  readonly chapterSourceLinks: ChapterSourceLinkRepositoryPort;
  readonly storageObjects: StorageObjectRepositoryPort;
  readonly storagePlacements: StoragePlacementRepositoryPort;
  readonly diagnosticsEvents: DiagnosticsEventRepositoryPort;
}
