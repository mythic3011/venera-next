import type {
  StorageBackendId,
  StorageObjectId,
  StoragePlacementId,
} from "./identifiers.js";

export const STORAGE_BACKEND_KINDS = [
  "local_app_data",
  "webdav",
  "future",
] as const;

export type StorageBackendKind = (typeof STORAGE_BACKEND_KINDS)[number];

export const STORAGE_OBJECT_KINDS = [
  "page_image",
  "cover",
  "archive",
  "backup",
  "cache",
] as const;

export type StorageObjectKind = (typeof STORAGE_OBJECT_KINDS)[number];

export const STORAGE_PLACEMENT_ROLES = [
  "authority",
  "cache",
  "mirror",
  "staging",
] as const;

export type StoragePlacementRole = (typeof STORAGE_PLACEMENT_ROLES)[number];

export const STORAGE_SYNC_STATUSES = [
  "pending",
  "uploading",
  "synced",
  "failed",
  "evicted",
] as const;

export type StorageSyncStatus = (typeof STORAGE_SYNC_STATUSES)[number];

export interface StorageBackend {
  readonly id: StorageBackendId;
  readonly backendKey: string;
  readonly displayName: string;
  readonly backendKind: StorageBackendKind;
  readonly configJson: string;
  readonly secretRef?: string;
  readonly isEnabled: boolean;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface StorageObject {
  readonly id: StorageObjectId;
  readonly objectKind: StorageObjectKind;
  readonly contentHash?: string;
  readonly sizeBytes?: number;
  readonly mimeType?: string;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface StoragePlacement {
  readonly id: StoragePlacementId;
  readonly storageObjectId: StorageObjectId;
  readonly storageBackendId: StorageBackendId;
  readonly objectKey: string;
  readonly role: StoragePlacementRole;
  readonly syncStatus: StorageSyncStatus;
  readonly lastVerifiedAt?: Date;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}
