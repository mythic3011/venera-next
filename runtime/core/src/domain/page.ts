import type {
  ChapterId,
  PageId,
  PageOrderId,
  PageOrderItemId,
  StorageObjectId,
  ChapterSourceLinkId,
} from "./identifiers.js";

export const PAGE_ORDER_KEYS = [
  "source",
  "user",
  "import_detected",
  "custom",
] as const;

export type PageOrderKey = (typeof PAGE_ORDER_KEYS)[number];

export const PAGE_ORDER_TYPES = [
  "source",
  "user_override",
  "import_detected",
  "custom",
] as const;

export type PageOrderType = (typeof PAGE_ORDER_TYPES)[number];

export interface Page {
  readonly id: PageId;
  readonly chapterId: ChapterId;
  readonly pageIndex: number;
  readonly storageObjectId?: StorageObjectId;
  readonly chapterSourceLinkId?: ChapterSourceLinkId;
  readonly mimeType?: string;
  readonly width?: number;
  readonly height?: number;
  readonly checksum?: string;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface CreatePageInput {
  readonly id: PageId;
  readonly chapterId: ChapterId;
  readonly pageIndex: number;
  readonly storageObjectId?: StorageObjectId;
  readonly chapterSourceLinkId?: ChapterSourceLinkId;
  readonly mimeType?: string;
  readonly width?: number;
  readonly height?: number;
  readonly checksum?: string;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface PageOrder {
  readonly id: PageOrderId;
  readonly chapterId: ChapterId;
  readonly orderKey: PageOrderKey;
  readonly orderType: PageOrderType;
  readonly isActive: boolean;
  readonly pageCount: number;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface PageOrderItem {
  readonly id: PageOrderItemId;
  readonly pageOrderId: PageOrderId;
  readonly pageId: PageId;
  readonly sortIndex: number;
  readonly createdAt: Date;
}

export interface PageOrderWithItems {
  readonly order: PageOrder;
  readonly items: readonly PageOrderItem[];
}

export interface SetUserPageOrderInput {
  readonly chapterId: ChapterId;
  readonly pageIds: readonly PageId[];
  readonly updatedAt: Date;
}
