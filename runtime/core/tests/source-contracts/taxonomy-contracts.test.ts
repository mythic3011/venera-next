import { describe, expect, it } from "vitest";

import {
  validateCanonicalTags,
  validateLocalizedTagLabels,
  validateProviderTagMapping,
  type CanonicalTag,
  type CanonicalTagsDocument,
  type LocalizedTagLabelsDocument,
  type ProviderTagMappingDocument,
} from "../../src/index.js";

function createCanonicalTags(
  overrides: Partial<CanonicalTagsDocument> = {},
): CanonicalTagsDocument {
  return {
    schemaVersion: "1.0.0",
    tags: [
      {
        canonicalKey: "genre.action",
        namespace: "genre",
        defaultLabel: "Action",
        valueType: "enum",
        sortOrder: 1,
      },
      {
        canonicalKey: "theme.action",
        namespace: "theme",
        defaultLabel: "Action",
      },
    ],
    ...overrides,
  };
}

function createCanonicalTag(overrides: Partial<CanonicalTag> = {}): CanonicalTag {
  return {
    canonicalKey: "genre.action",
    namespace: "genre",
    defaultLabel: "Action",
    valueType: "enum",
    sortOrder: 1,
    ...overrides,
  };
}

function createLocalizedLabels(
  overrides: Partial<LocalizedTagLabelsDocument> = {},
): LocalizedTagLabelsDocument {
  return {
    schemaVersion: "1.0.0",
    locale: "zh-HK",
    labels: {
      "genre.action": "動作",
    },
    ...overrides,
  };
}

function createProviderMapping(
  overrides: Partial<ProviderTagMappingDocument> = {},
): ProviderTagMappingDocument {
  return {
    schemaVersion: "1.0.0",
    providerKey: "copymanga",
    sourceLocale: "zh-CN",
    mappings: [
      {
        remoteTagKey: "热血",
        remoteLabel: "热血",
        canonicalKey: "theme.action",
        confidence: "manual",
      },
    ],
    ...overrides,
  };
}

describe("validateCanonicalTags", () => {
  it("accepts a valid canonical tags document", () => {
    const result = validateCanonicalTags(createCanonicalTags());

    expect(result.ok).toBe(true);
  });

  it("rejects duplicate canonicalKey values", () => {
    const result = validateCanonicalTags(
      createCanonicalTags({
        tags: [
          createCanonicalTag(),
          createCanonicalTag(),
        ],
      }),
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("TAG_TAXONOMY_INVALID");
    }
  });

  it("rejects invalid namespaces and value types", () => {
    const result = validateCanonicalTags({
      schemaVersion: "1.0.0",
      tags: [
        {
          canonicalKey: "genre.action",
          namespace: "unknown",
          defaultLabel: "Action",
          valueType: "invalid",
        },
      ],
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("TAG_TAXONOMY_INVALID");
    }
  });
});

describe("validateLocalizedTagLabels", () => {
  it("accepts a valid localized label file", () => {
    const canonicalTags = validateCanonicalTags(createCanonicalTags());
    expect(canonicalTags.ok).toBe(true);

    const result = validateLocalizedTagLabels(
      createLocalizedLabels(),
      canonicalTags.ok
        ? { knownCanonicalKeys: canonicalTags.value.tags.map((tag) => tag.canonicalKey) }
        : undefined,
    );

    expect(result.ok).toBe(true);
  });

  it("rejects unknown canonical keys when canonical context is supplied", () => {
    const result = validateLocalizedTagLabels(
      createLocalizedLabels({
        labels: {
          "genre.unknown": "未知",
        },
      }),
      { knownCanonicalKeys: ["genre.action"] },
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("TAG_TAXONOMY_INVALID");
    }
  });
});

describe("validateProviderTagMapping", () => {
  it("accepts a valid provider mapping document", () => {
    const result = validateProviderTagMapping(
      createProviderMapping(),
      {
        expectedProviderKey: "copymanga",
        knownCanonicalKeys: ["theme.action"],
      },
    );

    expect(result.ok).toBe(true);
  });

  it("rejects providerKey mismatches", () => {
    const result = validateProviderTagMapping(
      createProviderMapping(),
      { expectedProviderKey: "ehentai" },
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("TAG_MAPPING_INVALID");
    }
  });

  it("rejects unknown canonical keys", () => {
    const result = validateProviderTagMapping(
      createProviderMapping(),
      {
        expectedProviderKey: "copymanga",
        knownCanonicalKeys: ["genre.action"],
      },
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("TAG_MAPPING_INVALID");
    }
  });

  it("rejects invalid confidence values", () => {
    const result = validateProviderTagMapping({
      ...createProviderMapping(),
      mappings: [
        {
          remoteTagKey: "热血",
          remoteLabel: "热血",
          canonicalKey: "theme.action",
          confidence: "guess",
        },
      ],
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("TAG_MAPPING_INVALID");
    }
  });

  it("does not auto-merge same labels across namespaces", () => {
    const canonicalTags = validateCanonicalTags(createCanonicalTags());
    expect(canonicalTags.ok).toBe(true);

    const result = validateProviderTagMapping(
      createProviderMapping({
        mappings: [
          {
            remoteTagKey: "action",
            remoteLabel: "Action",
            canonicalKey: "genre.action",
            confidence: "manual",
          },
          {
            remoteTagKey: "action-theme",
            remoteLabel: "Action",
            canonicalKey: "theme.action",
            confidence: "auto_high",
          },
        ],
      }),
      canonicalTags.ok
        ? {
          expectedProviderKey: "copymanga",
          knownCanonicalKeys: canonicalTags.value.tags.map((tag) => tag.canonicalKey),
        }
        : undefined,
    );

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.mappings).toHaveLength(2);
    }
  });
});
