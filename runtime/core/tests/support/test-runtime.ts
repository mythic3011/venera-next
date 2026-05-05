import { randomUUID } from "node:crypto";

import { sql } from "kysely";

import {
  createCoreRuntime,
  type CoreRuntime,
} from "../../src/index.js";

export async function createTestRuntime(): Promise<CoreRuntime> {
  return createCoreRuntime({
    databasePath: ":memory:",
  });
}

export function nextId(): string {
  return randomUUID();
}

export async function insertComicFixture(
  runtime: CoreRuntime,
  input: {
    comicId?: string;
    chapterIds?: readonly string[];
    pageCount?: number;
    title?: string;
  } = {},
): Promise<{
  comicId: string;
  chapterIds: readonly string[];
  pageIds: readonly string[];
}> {
  const now = new Date().toISOString();
  const comicId = input.comicId ?? nextId();
  const chapterIds = input.chapterIds ?? [nextId()];
  const pageIds: string[] = [];
  const title = input.title ?? "Fixture Comic";

  await sql`
    INSERT INTO comics (id, normalized_title, origin_hint, created_at, updated_at)
    VALUES (${comicId}, ${title.toLowerCase()}, 'local', ${now}, ${now})
  `.execute(runtime.db);

  await sql`
    INSERT INTO comic_metadata (comic_id, title, created_at, updated_at)
    VALUES (${comicId}, ${title}, ${now}, ${now})
  `.execute(runtime.db);

  await sql`
    INSERT INTO comic_titles (id, comic_id, title, normalized_title, title_kind, created_at)
    VALUES (${nextId()}, ${comicId}, ${title}, ${title.toLowerCase()}, 'primary', ${now})
  `.execute(runtime.db);

  for (const [index, chapterId] of chapterIds.entries()) {
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
        ${index + 1},
        ${`Chapter ${index + 1}`},
        ${`Chapter ${index + 1}`},
        ${now},
        ${now}
      )
    `.execute(runtime.db);
  }

  const chapterId = chapterIds[0];
  const pageCount = input.pageCount ?? 3;
  const orderId = nextId();

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
      ${pageCount},
      ${now},
      ${now}
    )
  `.execute(runtime.db);

  for (let pageIndex = 0; pageIndex < pageCount; pageIndex += 1) {
    const pageId = nextId();
    pageIds.push(pageId);

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
        1000,
        1600,
        ${`checksum-${pageIndex}`},
        ${now},
        ${now}
      )
    `.execute(runtime.db);

    await sql`
      INSERT INTO page_order_items (
        id,
        page_order_id,
        page_id,
        sort_index,
        created_at
      )
      VALUES (
        ${nextId()},
        ${orderId},
        ${pageId},
        ${pageIndex},
        ${now}
      )
    `.execute(runtime.db);
  }

  return {
    comicId,
    chapterIds,
    pageIds,
  };
}
