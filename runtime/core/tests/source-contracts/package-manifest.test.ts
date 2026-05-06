import { describe, expect, it } from "vitest";

import {
  validateSourcePackageChecksums,
  validateSourcePackageManifest,
  type SourcePackageChecksums,
  type SourcePackageManifest,
} from "../../src/index.js";

const UPPER_HASH = "ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789";
const LOWER_HASH = UPPER_HASH.toLowerCase();

function createPackageManifest(
  overrides: Partial<SourcePackageManifest> = {},
): SourcePackageManifest {
  return {
    schemaVersion: "1.0.0",
    packageKey: "copymanga",
    providerKey: "copymanga",
    displayName: "CopyManga",
    version: "1.2.3",
    runtime: {
      kind: "module",
      entrypoint: "dist/index.js",
      apiVersion: "1",
    },
    capabilities: ["search", "detail"],
    permissions: ["network.https"],
    integrity: {
      archiveSha256: LOWER_HASH,
      entrypointSha256: LOWER_HASH,
    },
    endpoints: {
      baseUrl: "https://api.example.com",
    },
    taxonomy: {
      mappingFiles: ["taxonomy/mapping.json"],
    },
    ...overrides,
  };
}

function createChecksums(
  overrides: Partial<SourcePackageChecksums> = {},
): SourcePackageChecksums {
  return {
    files: [
      {
        path: "dist/index.js",
        sha256: LOWER_HASH,
      },
    ],
    packageSha256: LOWER_HASH,
    ...overrides,
  };
}

describe("validateSourcePackageManifest", () => {
  it("accepts a valid package manifest", () => {
    const result = validateSourcePackageManifest(createPackageManifest());

    expect(result.ok).toBe(true);
  });

  it("rejects legacy provider-only payloads", () => {
    const result = validateSourcePackageManifest({
      schemaVersion: "1.0.0",
      provider: "copymanga",
      displayName: "CopyManga",
      version: "1.2.3",
      runtime: {
        kind: "module",
        entrypoint: "dist/index.js",
        apiVersion: "1",
      },
      capabilities: [],
      permissions: [],
      integrity: {
        archiveSha256: LOWER_HASH,
        entrypointSha256: LOWER_HASH,
      },
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_MANIFEST_INVALID");
    }
  });

  it("rejects payloads with displayName but missing providerKey or packageKey", () => {
    const payload = createPackageManifest();
    delete (payload as Partial<SourcePackageManifest>).providerKey;
    delete (payload as Partial<SourcePackageManifest>).packageKey;

    const result = validateSourcePackageManifest(payload);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_MANIFEST_INVALID");
    }
  });

  it("rejects missing runtime entrypoint and apiVersion", () => {
    const payload = createPackageManifest();
    payload.runtime = {
      kind: "module",
      entrypoint: undefined as never,
      apiVersion: undefined as never,
    };

    const result = validateSourcePackageManifest(payload);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_MANIFEST_INVALID");
    }
  });

  it("rejects missing integrity hashes", () => {
    const payload = createPackageManifest();
    payload.integrity = {
      archiveSha256: undefined as never,
      entrypointSha256: undefined as never,
    };

    const result = validateSourcePackageManifest(payload);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_MANIFEST_INVALID");
    }
  });

  it("rejects previousProviderKeys and providerLineageId", () => {
    const result = validateSourcePackageManifest({
      ...createPackageManifest(),
      previousProviderKeys: ["legacy"],
      providerLineageId: "copymanga-lineage",
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_MANIFEST_INVALID");
    }
  });

  it("rejects unknown identity-related fields instead of stripping them", () => {
    const result = validateSourcePackageManifest({
      ...createPackageManifest(),
      providerAliases: ["copy-manga"],
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_MANIFEST_INVALID");
    }
  });

  it("normalizes uppercase SHA-256 hashes to lowercase", () => {
    const result = validateSourcePackageManifest(
      createPackageManifest({
        integrity: {
          archiveSha256: UPPER_HASH,
          entrypointSha256: UPPER_HASH,
        },
      }),
    );

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.integrity.archiveSha256).toBe(LOWER_HASH);
      expect(result.value.integrity.entrypointSha256).toBe(LOWER_HASH);
    }
  });
});

describe("validateSourcePackageChecksums", () => {
  it("accepts a valid checksums file", () => {
    const result = validateSourcePackageChecksums(createChecksums());

    expect(result.ok).toBe(true);
  });

  it("rejects duplicate file paths", () => {
    const result = validateSourcePackageChecksums(
      createChecksums({
        files: [
          {
            path: "dist/index.js",
            sha256: LOWER_HASH,
          },
          {
            path: "dist/index.js",
            sha256: LOWER_HASH,
          },
        ],
      }),
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_TAXONOMY_INVALID");
    }
  });

  it("rejects invalid SHA-256 shapes", () => {
    const result = validateSourcePackageChecksums(
      createChecksums({
        packageSha256: "not-a-hash",
      }),
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_TAXONOMY_INVALID");
    }
  });

  it("normalizes uppercase SHA-256 values to lowercase", () => {
    const result = validateSourcePackageChecksums(
      createChecksums({
        files: [
          {
            path: "dist/index.js",
            sha256: UPPER_HASH,
          },
        ],
        packageSha256: UPPER_HASH,
      }),
    );

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.files[0]?.sha256).toBe(LOWER_HASH);
      expect(result.value.packageSha256).toBe(LOWER_HASH);
    }
  });
});
