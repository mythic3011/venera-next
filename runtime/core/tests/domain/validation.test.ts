import { describe, expect, it } from "vitest";

import {
  parseComicId,
  parseChapterId,
} from "../../src/domain/identifiers.js";
import {
  normalizeTitle,
  parseDisplayTitle,
  parseNormalizedTitle,
} from "../../src/domain/comic.js";

describe("domain validation", () => {
  it("rejects reserved placeholder and encoded-route ids", () => {
    expect(parseComicId("").ok).toBe(false);
    expect(parseComicId("_").ok).toBe(false);
    expect(parseChapterId("__imported__").ok).toBe(false);
    expect(parseComicId("local:local:123:_").ok).toBe(false);
  });

  it("accepts valid UUID ids", () => {
    const result = parseComicId("123e4567-e89b-42d3-a456-426614174000");
    expect(result.ok).toBe(true);
  });

  it("normalizes and validates titles", () => {
    expect(normalizeTitle("  Hello   WORLD ")).toBe("hello world");
    expect(parseDisplayTitle("  Good Title ").ok).toBe(true);
    expect(parseDisplayTitle("   ").ok).toBe(false);

    const normalized = parseNormalizedTitle("  Good Title ");
    expect(normalized.ok).toBe(true);
    if (normalized.ok) {
      expect(normalized.value).toBe("good title");
    }
  });
});
