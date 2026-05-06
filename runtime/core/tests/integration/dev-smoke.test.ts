import { existsSync, readFileSync } from "node:fs";
import { rm } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

import { afterEach, describe, expect, it } from "vitest";

import { corePackageRoot } from "../support/source-scan.js";

interface SmokeOptions {
  readonly keepDb?: boolean;
  readonly skipFixture?: boolean;
}

interface SmokeComicSummary {
  readonly id: string;
}

interface SmokeFixtureSummary {
  readonly chapterId: string;
  readonly pageIds: readonly string[];
  readonly pageCount: number;
}

interface SmokeResolvedTargetSummary {
  readonly chapterId: string;
  readonly pageIndex: number;
  readonly sourceKind: string;
  readonly resolutionReason: string;
}

interface SmokeOpenReaderSummary {
  readonly chapterId: string;
  readonly pageCount: number;
  readonly resolvedPageIndex: number;
}

interface SmokeUpdateReaderPositionSummary {
  readonly status: string;
  readonly pageIndex: number;
}

interface SmokeReaderSessionSummary {
  readonly comicId: string;
  readonly chapterId: string;
  readonly pageId?: string;
  readonly pageIndex: number;
}

interface SmokeErrorSummary {
  readonly code: string;
  readonly message: string;
  readonly details?: unknown;
}

interface SmokeSuccessResult {
  readonly ok: true;
  readonly keptDb: boolean;
  readonly databasePath: string;
  readonly comic: SmokeComicSummary;
  readonly fixture: SmokeFixtureSummary;
  readonly resolvedTarget: SmokeResolvedTargetSummary;
  readonly openReader: SmokeOpenReaderSummary;
  readonly updateReaderPosition: SmokeUpdateReaderPositionSummary;
  readonly readerSession: SmokeReaderSessionSummary;
  readonly seededSourcePlatforms: readonly string[];
}

interface SmokeFailureResult {
  readonly ok: false;
  readonly keptDb: boolean;
  readonly databasePath?: string;
  readonly fixture: null;
  readonly error: SmokeErrorSummary;
}

type SmokeResult = SmokeSuccessResult | SmokeFailureResult;

interface SmokeModule {
  runCoreSmoke(options?: SmokeOptions): Promise<SmokeResult>;
  parseSmokeArgs(args: readonly string[]): SmokeOptions;
}

const keptDatabasePaths = new Set<string>();

function getSmokeModulePath(): string {
  return resolve(corePackageRoot, "src", "cli", "dev-smoke.ts");
}

function getRepoWrapperPath(): string {
  return resolve(corePackageRoot, "..", "..", "scripts", "core-smoke.ts");
}

async function loadSmokeModule(): Promise<SmokeModule> {
  const modulePath = getSmokeModulePath();
  if (!existsSync(modulePath)) {
    throw new Error(`Missing smoke module: ${modulePath}`);
  }

  const moduleUrl = pathToFileURL(modulePath).href;
  const imported = await import(moduleUrl) as Partial<SmokeModule>;

  if (typeof imported.runCoreSmoke !== "function") {
    throw new Error(`Smoke module does not export runCoreSmoke(): ${modulePath}`);
  }

  if (typeof imported.parseSmokeArgs !== "function") {
    throw new Error(`Smoke module does not export parseSmokeArgs(): ${modulePath}`);
  }

  return imported as SmokeModule;
}

function rememberKeptDatabase(result: SmokeResult): void {
  if (result.keptDb && typeof result.databasePath === "string" && result.databasePath.length > 0) {
    keptDatabasePaths.add(result.databasePath);
  }
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function assertNoSnakeCaseKeys(value: unknown, path = "result"): void {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => {
      assertNoSnakeCaseKeys(entry, `${path}[${index}]`);
    });
    return;
  }

  if (!isPlainObject(value)) {
    return;
  }

  for (const [key, nestedValue] of Object.entries(value)) {
    expect(key, `snake_case key exposed at ${path}.${key}`).not.toMatch(/^[a-z0-9]+(?:_[a-z0-9]+)+$/);
    assertNoSnakeCaseKeys(nestedValue, `${path}.${key}`);
  }
}

function parseJsonRoundTrip<TValue>(value: TValue): TValue {
  return JSON.parse(JSON.stringify(value)) as TValue;
}

afterEach(async () => {
  await Promise.all(
    [...keptDatabasePaths].map(async (databasePath) => {
      keptDatabasePaths.delete(databasePath);
      await rm(databasePath, { force: true });
    }),
  );
});

describe("dev smoke harness", () => {
  it("returns a stable success result for the canonical runtime smoke path", async () => {
    const { runCoreSmoke } = await loadSmokeModule();

    const result = await runCoreSmoke();
    rememberKeptDatabase(result);

    expect(result.ok).toBe(true);
    if (!result.ok) {
      return;
    }

    const parsed = parseJsonRoundTrip(result);

    expect(parsed.ok).toBe(true);
    expect(parsed.keptDb).toBe(false);
    expect(typeof parsed.databasePath).toBe("string");
    expect(parsed.databasePath.length).toBeGreaterThan(0);

    expect(parsed.comic.id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    );

    expect(parsed.fixture.chapterId).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    );
    expect(parsed.fixture.pageCount).toBeGreaterThan(0);
    expect(parsed.fixture.pageIds).toHaveLength(parsed.fixture.pageCount);
    expect(new Set(parsed.fixture.pageIds).size).toBe(parsed.fixture.pageIds.length);

    expect(parsed.resolvedTarget.chapterId).toBe(parsed.fixture.chapterId);
    expect(parsed.resolvedTarget.chapterId).not.toMatch(/^synthetic:/);
    expect(parsed.resolvedTarget.sourceKind).toBe("local");
    expect(parsed.resolvedTarget.resolutionReason).toBe("first_canonical_chapter");
    expect(parsed.resolvedTarget.pageIndex).toBe(0);

    expect(parsed.openReader.chapterId).toBe(parsed.fixture.chapterId);
    expect(parsed.openReader.pageCount).toBe(parsed.fixture.pageCount);
    expect(parsed.openReader.resolvedPageIndex).toBe(parsed.resolvedTarget.pageIndex);

    expect(parsed.updateReaderPosition.status).toBe("written");
    expect(parsed.updateReaderPosition.pageIndex).toBe(parsed.readerSession.pageIndex);
    expect(parsed.readerSession.comicId).toBe(parsed.comic.id);
    expect(parsed.readerSession.chapterId).toBe(parsed.fixture.chapterId);
    expect(parsed.readerSession.pageId).toBe(parsed.fixture.pageIds[parsed.readerSession.pageIndex]);

    expect(parsed.seededSourcePlatforms).toContain("local");
    assertNoSnakeCaseKeys(parsed);
  });

  it("returns the unresolved-local-target failure when fixture creation is skipped", async () => {
    const { runCoreSmoke } = await loadSmokeModule();

    const result = await runCoreSmoke({ skipFixture: true });
    rememberKeptDatabase(result);

    expect(result.ok).toBe(false);
    if (result.ok) {
      return;
    }

    const parsed = parseJsonRoundTrip(result);

    expect(parsed.ok).toBe(false);
    expect(parsed.keptDb).toBe(false);
    expect(parsed.fixture).toBeNull();
    expect(parsed.error.code).toBe("READER_UNRESOLVED_LOCAL_TARGET");
    expect(typeof parsed.error.message).toBe("string");
    expect(parsed.error.message.length).toBeGreaterThan(0);
    assertNoSnakeCaseKeys(parsed);
  });

  it("parses keep-db and skip-fixture flags for thin CLI adapters", async () => {
    const { parseSmokeArgs } = await loadSmokeModule();

    expect(parseSmokeArgs([])).toEqual({
      keepDb: false,
      skipFixture: false,
    });
    expect(parseSmokeArgs(["--keep-db"])).toEqual({
      keepDb: true,
      skipFixture: false,
    });
    expect(parseSmokeArgs(["--skip-fixture"])).toEqual({
      keepDb: false,
      skipFixture: true,
    });
    expect(parseSmokeArgs(["--keep-db", "--skip-fixture"])).toEqual({
      keepDb: true,
      skipFixture: true,
    });
  });

  it("keeps the repo wrapper thin and free of direct db or repository imports", () => {
    const wrapperPath = getRepoWrapperPath();
    expect(existsSync(wrapperPath)).toBe(true);

    const wrapperSource = readFileSync(wrapperPath, "utf8");
    expect(wrapperSource).toContain('runCoreSmoke');
    expect(wrapperSource).not.toMatch(/src\/db\//);
    expect(wrapperSource).not.toMatch(/src\/repositories\//);
    expect(wrapperSource).not.toMatch(/kysely/);
  });
});
