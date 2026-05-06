import type {
  ChapterId,
  ChapterSourceLinkId,
  ComicId,
  SourceLinkId,
  SourcePlatformId,
} from "./identifiers.js";

export const SOURCE_PLATFORM_KINDS = [
  "local",
  "remote",
  "virtual",
] as const;

export type SourcePlatformKind = (typeof SOURCE_PLATFORM_KINDS)[number];

export const SOURCE_LINK_STATUSES = [
  "active",
  "candidate",
  "rejected",
  "stale",
] as const;

export type SourceLinkStatus = (typeof SOURCE_LINK_STATUSES)[number];

export const SOURCE_LINK_CONFIDENCES = [
  "manual",
  "auto_high",
  "auto_low",
] as const;

export type SourceLinkConfidence = (typeof SOURCE_LINK_CONFIDENCES)[number];

export interface SourcePlatform {
  readonly id: SourcePlatformId;
  readonly canonicalKey: string;
  readonly displayName: string;
  readonly kind: SourcePlatformKind;
  readonly isEnabled: boolean;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface SourceLink {
  readonly id: SourceLinkId;
  readonly comicId: ComicId;
  readonly sourcePlatformId: SourcePlatformId;
  readonly remoteWorkId: string;
  readonly remoteUrl?: string;
  readonly displayTitle?: string;
  readonly linkStatus: SourceLinkStatus;
  readonly confidence: SourceLinkConfidence;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface ChapterSourceLink {
  readonly id: ChapterSourceLinkId;
  readonly chapterId: ChapterId;
  readonly sourceLinkId: SourceLinkId;
  readonly remoteChapterId: string;
  readonly remoteUrl?: string;
  readonly remoteLabel?: string;
  readonly linkStatus: SourceLinkStatus;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface ProviderWorkRef {
  readonly sourcePlatformId: SourcePlatformId;
  readonly remoteWorkId: string;
}
