import { describe, expect, it } from "vitest";

import {
  validateSourceRepositoryIndex,
  type SourceRepositoryPackageEntry,
  type SourceRepositoryIndex,
} from "../../src/index.js";

const UPPER_HASH = "ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789";

function createRepositoryIndex(
  overrides: Partial<SourceRepositoryIndex> = {},
): SourceRepositoryIndex {
  return {
    schemaVersion: "1.0.0",
    repositoryKey: "community",
    displayName: "Community Sources",
    updatedAt: "2026-05-05T00:00:00.000Z",
    packages: [
      {
        packageKey: "copymanga",
        providerKey: "copymanga",
        displayName: "CopyManga",
        version: "1.2.3",
        manifestUrl: "packages/copymanga/manifest.json",
        packageUrl: "packages/copymanga/package.tgz",
        sha256: UPPER_HASH.toLowerCase(),
        minCoreVersion: "0.1.0",
        capabilities: ["search", "detail"],
        permissions: ["network.https"],
      },
    ],
    ...overrides,
  };
}

function createRepositoryPackageEntry(
  overrides: Partial<SourceRepositoryPackageEntry> = {},
): SourceRepositoryPackageEntry {
  return {
    packageKey: "copymanga",
    providerKey: "copymanga",
    displayName: "CopyManga",
    version: "1.2.3",
    manifestUrl: "packages/copymanga/manifest.json",
    packageUrl: "packages/copymanga/package.tgz",
    sha256: UPPER_HASH.toLowerCase(),
    minCoreVersion: "0.1.0",
    capabilities: ["search", "detail"],
    permissions: ["network.https"],
    ...overrides,
  };
}

describe("validateSourceRepositoryIndex", () => {
  it("accepts a valid repository index", () => {
    const result = validateSourceRepositoryIndex(createRepositoryIndex());

    expect(result.ok).toBe(true);
  });

  it("rejects missing repositoryKey", () => {
    const payload = createRepositoryIndex();
    delete (payload as Partial<SourceRepositoryIndex>).repositoryKey;

    const result = validateSourceRepositoryIndex(payload);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_REPOSITORY_INDEX_INVALID");
    }
  });

  it("rejects missing packageKey, providerKey, manifestUrl, packageUrl, and sha256", () => {
    const payload = {
      ...createRepositoryIndex(),
      packages: [
        {
          displayName: "CopyManga",
          version: "1.2.3",
          minCoreVersion: "0.1.0",
          capabilities: ["search", "detail"],
          permissions: ["network.https"],
        },
      ],
    };

    const result = validateSourceRepositoryIndex(payload);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_REPOSITORY_INDEX_INVALID");
    }
  });

  it("accepts relative manifestUrl and packageUrl", () => {
    const result = validateSourceRepositoryIndex(
      createRepositoryIndex({
        packages: [
          createRepositoryPackageEntry({
            manifestUrl: "./manifest.json",
            packageUrl: "../packages/copymanga.zip",
          }),
        ],
      }),
    );

    expect(result.ok).toBe(true);
  });

  it("accepts absolute https URLs by default", () => {
    const result = validateSourceRepositoryIndex(
      createRepositoryIndex({
        packages: [
          createRepositoryPackageEntry({
            manifestUrl: "https://example.com/manifest.json",
            packageUrl: "https://example.com/package.zip",
          }),
        ],
      }),
    );

    expect(result.ok).toBe(true);
  });

  it("rejects absolute http URLs by default", () => {
    const result = validateSourceRepositoryIndex(
      createRepositoryIndex({
        packages: [
          createRepositoryPackageEntry({
            manifestUrl: "http://example.com/manifest.json",
            packageUrl: "http://example.com/package.zip",
          }),
        ],
      }),
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_REPOSITORY_INDEX_INVALID");
    }
  });

  it("accepts absolute http URLs only with explicit policy opt-in", () => {
    const result = validateSourceRepositoryIndex(
      createRepositoryIndex({
        packages: [
          createRepositoryPackageEntry({
            manifestUrl: "http://example.com/manifest.json",
            packageUrl: "http://example.com/package.zip",
          }),
        ],
      }),
      { urlPolicy: { allowHttp: true } },
    );

    expect(result.ok).toBe(true);
  });

  it.each([
    "file:///tmp/package.zip",
    "javascript:alert(1)",
    "data:text/plain;base64,SGVsbG8=",
    "",
  ])("rejects disallowed package URLs: %s", (packageUrl) => {
    const result = validateSourceRepositoryIndex(
      createRepositoryIndex({
        packages: [
          createRepositoryPackageEntry({
            manifestUrl: packageUrl,
            packageUrl,
          }),
        ],
      }),
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_REPOSITORY_INDEX_INVALID");
    }
  });
});
