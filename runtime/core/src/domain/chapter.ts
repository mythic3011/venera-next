import type { ComicId, ChapterId } from "./identifiers.js";

export const CHAPTER_KINDS = [
  "season",
  "volume",
  "chapter",
  "episode",
  "oneshot",
  "group",
] as const;

export type ChapterKind = (typeof CHAPTER_KINDS)[number];

export interface Chapter {
  readonly id: ChapterId;
  readonly comicId: ComicId;
  readonly parentChapterId?: ChapterId;
  readonly chapterKind: ChapterKind;
  readonly chapterNumber: number;
  readonly title?: string;
  readonly displayLabel?: string;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface ChapterTreeNode {
  readonly chapter: Chapter;
  readonly children: readonly ChapterTreeNode[];
}

export interface CreateChapterInput {
  readonly id: ChapterId;
  readonly comicId: ComicId;
  readonly parentChapterId?: ChapterId;
  readonly chapterKind: ChapterKind;
  readonly chapterNumber: number;
  readonly title?: string;
  readonly displayLabel?: string;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface UpdateChapterInput {
  readonly id: ChapterId;
  readonly parentChapterId?: ChapterId;
  readonly chapterKind?: ChapterKind;
  readonly chapterNumber?: number;
  readonly title?: string;
  readonly displayLabel?: string;
  readonly updatedAt: Date;
}

export interface ListChapterChildrenInput {
  readonly comicId: ComicId;
  readonly parentChapterId?: ChapterId;
}
