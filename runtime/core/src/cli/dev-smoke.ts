import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

import { DevFixtureBuilder, type DevFixtureResult } from "./dev-fixtures.js";
import { createCoreRuntime } from "../runtime/create-core-runtime.js";
import type { CreatedCanonicalComic } from "../domain/comic.js";
import type { OpenReaderResult } from "../domain/reader.js";
import type { CoreError } from "../shared/errors.js";
import { isErr } from "../shared/result.js";

export interface SmokeCliOptions {
  readonly keepDb: boolean;
  readonly skipFixture: boolean;
}

export interface CoreSmokeSuccess {
  readonly ok: true;
  readonly databasePath: string;
  readonly keptDb: boolean;
  readonly comic: {
    readonly id: string;
    readonly title: string;
    readonly normalizedTitle: string;
    readonly originHint: string;
  };
  readonly fixture: {
    readonly chapterId: string;
    readonly pageIds: readonly string[];
    readonly pageCount: number;
  };
  readonly resolvedTarget: {
    readonly comicId: string;
    readonly chapterId: string;
    readonly pageIndex: number;
    readonly sourceKind: string;
    readonly resolutionReason: string;
    readonly pageId?: string;
    readonly sourceLinkId?: string;
    readonly chapterSourceLinkId?: string;
  };
  readonly openReader: {
    readonly chapterId: string;
    readonly pageCount: number;
    readonly resolvedPageIndex: number;
  };
  readonly updateReaderPosition: {
    readonly status: string;
    readonly pageIndex: number;
  };
  readonly readerSession: {
    readonly id: string;
    readonly comicId: string;
    readonly chapterId: string;
    readonly pageIndex: number;
    readonly readerMode: string;
    readonly createdAt: string;
    readonly updatedAt: string;
    readonly pageId?: string;
    readonly sourceLinkId?: string;
    readonly chapterSourceLinkId?: string;
  };
  readonly seededSourcePlatforms: readonly string[];
}

export interface CoreSmokeFailure {
  readonly ok: false;
  readonly keptDb: boolean;
  readonly fixture: {
    readonly chapterId: string;
    readonly pageIds: readonly string[];
    readonly pageCount: number;
  } | null;
  readonly databasePath?: string;
  readonly error: {
    readonly code: string;
    readonly message: string;
    readonly details?: Record<string, string | number | boolean | null>;
  };
}

export type CoreSmokeResult = CoreSmokeSuccess | CoreSmokeFailure;

function withOptional<
  TValue extends object,
  TKey extends string,
  TOptionalValue,
>(
  value: TValue,
  key: TKey,
  optionalValue: TOptionalValue | undefined,
): TValue & Partial<Record<TKey, TOptionalValue>> {
  if (optionalValue === undefined) {
    return value;
  }

  return {
    ...value,
    [key]: optionalValue,
  };
}

function normalizeError(
  error: CoreError | Error | unknown,
): CoreSmokeFailure["error"] {
  if (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    "message" in error &&
    typeof error.code === "string" &&
    typeof error.message === "string"
  ) {
    return withOptional(
      {
        code: error.code,
        message: error.message,
      },
      "details",
      normalizeDetails("details" in error ? error.details : undefined),
    );
  }

  return {
    code: "SMOKE_ADAPTER_ERROR",
    message: "Runtime core smoke failed unexpectedly.",
  };
}

function normalizeDetails(
  value: unknown,
): Record<string, string | number | boolean | null> | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return undefined;
  }

  const normalizedEntries = Object.entries(value).flatMap(([key, entryValue]) => {
    if (
      typeof entryValue === "string" ||
      typeof entryValue === "number" ||
      typeof entryValue === "boolean" ||
      entryValue === null
    ) {
      return [[key, entryValue] as const];
    }

    return [];
  });

  return normalizedEntries.length > 0
    ? Object.fromEntries(normalizedEntries)
    : undefined;
}

function formatFixture(
  fixture: DevFixtureResult | null,
): CoreSmokeSuccess["fixture"] | null {
  if (fixture === null) {
    return null;
  }

  return {
    chapterId: fixture.chapterId,
    pageIds: [...fixture.pageIds],
    pageCount: fixture.pageCount,
  };
}

function formatComic(comic: CreatedCanonicalComic): CoreSmokeSuccess["comic"] {
  return {
    id: comic.comic.id,
    title: comic.metadata.title,
    normalizedTitle: comic.comic.normalizedTitle,
    originHint: comic.comic.originHint,
  };
}

function formatResolvedTarget(
  openReader: OpenReaderResult,
): CoreSmokeSuccess["resolvedTarget"] {
  return withOptional(
    withOptional(
      withOptional(
        {
          comicId: openReader.target.comicId,
          chapterId: openReader.target.chapterId,
          pageIndex: openReader.target.pageIndex,
          sourceKind: openReader.target.sourceKind,
          resolutionReason: openReader.target.resolutionReason,
        },
        "pageId",
        openReader.target.pageId,
      ),
      "sourceLinkId",
      openReader.target.sourceLinkId,
    ),
    "chapterSourceLinkId",
    openReader.target.chapterSourceLinkId,
  );
}

function formatReaderSession(
  session: NonNullable<Awaited<ReturnType<typeof queryReaderSession>>>,
): CoreSmokeSuccess["readerSession"] {
  return withOptional(
    withOptional(
      withOptional(
        {
          id: session.id,
          comicId: session.comicId,
          chapterId: session.chapterId,
          pageIndex: session.pageIndex,
          readerMode: session.readerMode,
          createdAt: session.createdAt.toISOString(),
          updatedAt: session.updatedAt.toISOString(),
        },
        "pageId",
        session.pageId,
      ),
      "sourceLinkId",
      session.sourceLinkId,
    ),
    "chapterSourceLinkId",
    session.chapterSourceLinkId,
  );
}

async function cleanupTempDb(tempDirPath: string | undefined): Promise<boolean> {
  if (tempDirPath === undefined) {
    return false;
  }

  await rm(tempDirPath, {
    recursive: true,
    force: true,
  });

  return false;
}

async function queryReaderSession(
  runtime: Awaited<ReturnType<typeof createCoreRuntime>>,
  comicId: string,
) {
  const sessionResult = await runtime.repositories.readerSessions.getByComic(comicId as never);
  if (isErr(sessionResult)) {
    throw sessionResult.error;
  }

  if (sessionResult.value === null) {
    throw new Error("Smoke flow expected a persisted reader session.");
  }

  return sessionResult.value;
}

async function querySeededPlatforms(
  runtime: Awaited<ReturnType<typeof createCoreRuntime>>,
): Promise<readonly string[]> {
  const platformsResult = await runtime.repositories.sourcePlatforms.listEnabled();
  if (isErr(platformsResult)) {
    throw platformsResult.error;
  }

  const keys = platformsResult.value.map((platform) => platform.canonicalKey).sort();
  if (!keys.includes("local")) {
    throw new Error("Smoke flow expected the seeded local source platform.");
  }

  return keys;
}

export function parseSmokeArgs(argv: readonly string[]): SmokeCliOptions {
  let keepDb = false;
  let skipFixture = false;

  for (const arg of argv) {
    if (arg === "--keep-db") {
      keepDb = true;
      continue;
    }

    if (arg === "--skip-fixture") {
      skipFixture = true;
      continue;
    }

    throw new Error(`Unknown smoke argument: ${arg}`);
  }

  return {
    keepDb,
    skipFixture,
  };
}

export async function runCoreSmoke(
  options: Partial<SmokeCliOptions> = {},
): Promise<CoreSmokeResult> {
  const defaultOptions: SmokeCliOptions = {
    keepDb: false,
    skipFixture: false,
  };
  const requestedOptions: SmokeCliOptions = {
    keepDb: options.keepDb ?? false,
    skipFixture: options.skipFixture ?? false,
  };
  const normalizedOptions = {
    ...defaultOptions,
    ...requestedOptions,
  };

  const tempDirPath = await mkdtemp(join(tmpdir(), "venera-runtime-core-smoke-"));
  const databasePath = join(tempDirPath, "runtime-core-smoke.sqlite");

  let runtime: Awaited<ReturnType<typeof createCoreRuntime>> | undefined;
  let fixture: DevFixtureResult | null = null;
  let keptDb = normalizedOptions.keepDb;

  try {
    runtime = await createCoreRuntime({
      databasePath,
      migrate: true,
      seed: true,
    });

    const comicResult = await runtime.useCases.createCanonicalComic.execute({
      title: "Runtime Core Smoke Comic",
      originHint: "local",
    });
    if (isErr(comicResult)) {
      return {
        ok: false,
        databasePath,
        keptDb,
        fixture: null,
        error: normalizeError(comicResult.error),
      };
    }

    if (!normalizedOptions.skipFixture) {
      fixture = await new DevFixtureBuilder(runtime).createReaderFixture(comicResult.value.comic.id);
    }

    const resolvedTargetResult = await runtime.useCases.resolveReaderTarget.execute({
      comicId: comicResult.value.comic.id,
    });
    if (isErr(resolvedTargetResult)) {
      return {
        ok: false,
        databasePath,
        keptDb,
        fixture: formatFixture(fixture),
        error: normalizeError(resolvedTargetResult.error),
      };
    }

    const openReaderResult = await runtime.useCases.openReader.execute({
      comicId: comicResult.value.comic.id,
    });
    if (isErr(openReaderResult)) {
      return {
        ok: false,
        databasePath,
        keptDb,
        fixture: formatFixture(fixture),
        error: normalizeError(openReaderResult.error),
      };
    }

    const resolvedPageIndex = openReaderResult.value.target.pageIndex;
    const nextPageIndex = Math.min(
      resolvedPageIndex + 1,
      openReaderResult.value.pages.length - 1,
    );
    const nextPage = openReaderResult.value.pages[nextPageIndex];
    if (nextPage === undefined) {
      throw new Error("Smoke flow could not resolve the page to persist.");
    }

    const updateResult = await runtime.useCases.updateReaderPosition.execute({
      comicId: comicResult.value.comic.id,
      chapterId: openReaderResult.value.target.chapterId,
      pageId: nextPage.page.id,
      pageIndex: nextPageIndex,
      readerMode: "continuous",
      ...(openReaderResult.value.target.sourceLinkId === undefined
        ? {}
        : { sourceLinkId: openReaderResult.value.target.sourceLinkId }),
      ...(openReaderResult.value.target.chapterSourceLinkId === undefined
        ? {}
        : {
            chapterSourceLinkId:
              openReaderResult.value.target.chapterSourceLinkId,
          }),
    });
    if (isErr(updateResult)) {
      return {
        ok: false,
        databasePath,
        keptDb,
        fixture: formatFixture(fixture),
        error: normalizeError(updateResult.error),
      };
    }

    const readerSession = await queryReaderSession(runtime, comicResult.value.comic.id);
    const seededSourcePlatforms = await querySeededPlatforms(runtime);
    const formattedFixture = formatFixture(fixture);
    if (formattedFixture === null) {
      throw new Error("Smoke flow completed without a reader fixture.");
    }

    return {
      ok: true,
      databasePath,
      keptDb,
      comic: formatComic(comicResult.value),
      fixture: formattedFixture,
      resolvedTarget: formatResolvedTarget(openReaderResult.value),
      openReader: {
        chapterId: openReaderResult.value.chapter.id,
        pageCount: openReaderResult.value.pages.length,
        resolvedPageIndex,
      },
      updateReaderPosition: {
        status: updateResult.value.status,
        pageIndex: nextPageIndex,
      },
      readerSession: formatReaderSession(readerSession),
      seededSourcePlatforms,
    };
  } catch (error) {
    return withOptional(
      {
        ok: false,
        keptDb,
        fixture: formatFixture(fixture),
        error: normalizeError(error),
      },
      "databasePath",
      databasePath,
    );
  } finally {
    if (runtime !== undefined) {
      runtime.close();
    }

    if (!normalizedOptions.keepDb) {
      keptDb = await cleanupTempDb(tempDirPath);
    }
  }
}

export async function main(argv: readonly string[] = process.argv.slice(2)): Promise<void> {
  let result: CoreSmokeResult;

  try {
    const options = parseSmokeArgs(argv);
    result = await runCoreSmoke(options);
  } catch (error) {
    result = {
      ok: false,
      keptDb: false,
      fixture: null,
      error: normalizeError(error),
    };
  }

  console.log(JSON.stringify(result, null, 2));
  process.exitCode = result.ok ? 0 : 1;
}

const directRunArgv = process.argv[1];
if (
  directRunArgv !== undefined &&
  import.meta.url === pathToFileURL(directRunArgv).href
) {
  void main().catch((error: unknown) => {
    const normalizedError = normalizeError(error);
    console.error(JSON.stringify({
      ok: false,
      keptDb: false,
      fixture: null,
      error: normalizedError,
    }, null, 2));
    process.exitCode = 1;
  });
}
