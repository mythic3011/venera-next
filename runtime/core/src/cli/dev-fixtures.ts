import { randomUUID } from "node:crypto";

import { sql } from "kysely";

import type { CoreRuntime } from "../runtime/create-core-runtime.js";
import {
  parseChapterId,
  parsePageId,
  type ChapterId,
  type ComicId,
  type PageId,
} from "../domain/identifiers.js";
import { isErr } from "../shared/result.js";

export interface DevFixtureResult {
  readonly chapterId: ChapterId;
  readonly pageIds: readonly PageId[];
  readonly pageCount: number;
}

function nextUuid(): string {
  return randomUUID();
}

function requireChapterId(value: string): ChapterId {
  const parsed = parseChapterId(value);
  if (isErr(parsed)) {
    throw parsed.error;
  }

  return parsed.value;
}

function requirePageId(value: string): PageId {
  const parsed = parsePageId(value);
  if (isErr(parsed)) {
    throw parsed.error;
  }

  return parsed.value;
}

export class DevFixtureBuilder {
  constructor(private readonly runtime: CoreRuntime) {}

  async createReaderFixture(comicId: ComicId): Promise<DevFixtureResult> {
    const timestamp = new Date().toISOString();
    const chapterId = requireChapterId(nextUuid());
    const orderId = nextUuid();
    const pageIds = [
      requirePageId(nextUuid()),
      requirePageId(nextUuid()),
      requirePageId(nextUuid()),
    ] as const;

    await this.runtime.db.transaction().execute(async (transaction) => {
      // Dev-only raw writes stay here because production ports expose reader-facing
      // chapter/page/order reads but no create ports yet for smoke fixture assembly.
      await sql`
        INSERT INTO chapters (
          id,
          comic_id,
          parent_chapter_id,
          chapter_kind,
          chapter_number,
          title,
          display_label,
          created_at,
          updated_at
        )
        VALUES (
          ${chapterId},
          ${comicId},
          NULL,
          'chapter',
          1,
          'Chapter 1',
          'Chapter 1',
          ${timestamp},
          ${timestamp}
        )
      `.execute(transaction);

      await sql`
        INSERT INTO page_orders (
          id,
          chapter_id,
          order_key,
          order_type,
          is_active,
          page_count,
          created_at,
          updated_at
        )
        VALUES (
          ${orderId},
          ${chapterId},
          'source',
          'source',
          1,
          ${pageIds.length},
          ${timestamp},
          ${timestamp}
        )
      `.execute(transaction);

      for (const [pageIndex, pageId] of pageIds.entries()) {
        await sql`
          INSERT INTO pages (
            id,
            chapter_id,
            page_index,
            storage_object_id,
            chapter_source_link_id,
            mime_type,
            width,
            height,
            checksum,
            created_at,
            updated_at
          )
          VALUES (
            ${pageId},
            ${chapterId},
            ${pageIndex},
            NULL,
            NULL,
            'image/jpeg',
            1200,
            1800,
            ${`smoke-checksum-${pageIndex}`},
            ${timestamp},
            ${timestamp}
          )
        `.execute(transaction);

        await sql`
          INSERT INTO page_order_items (
            id,
            page_order_id,
            page_id,
            sort_index,
            created_at
          )
          VALUES (
            ${nextUuid()},
            ${orderId},
            ${pageId},
            ${pageIndex},
            ${timestamp}
          )
        `.execute(transaction);
      }
    });

    return {
      chapterId,
      pageIds,
      pageCount: pageIds.length,
    };
  }
}
