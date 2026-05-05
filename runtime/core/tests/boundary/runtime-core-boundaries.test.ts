import { describe, expect, it } from "vitest";

import {
  collectModuleSpecifiers,
  listTypeScriptFiles,
  readCoreFile,
  relativeToCore,
  stripComments
} from "../support/source-scan.js";

const forbiddenLegacyPatterns = [
  /\.dart$/i,
  /package:flutter\b/i,
  /(?:^|\/)lib\/legacy(?:\/|$)/,
  /(?:^|\/)\.\.\/venera-core(?:\/|$)/,
  /(?:^|\/)\.\.\/\.\.\/venera-core(?:\/|$)/,
  /(?:^|\/)venera-core(?:\/|$)/
];

function findForbiddenImports(relativeDir: string, patterns: RegExp[]): string[] {
  return listTypeScriptFiles(relativeDir).flatMap((filePath) => {
    const sourceText = readCoreFile(relativeToCore(filePath));
    if (sourceText === null) {
      return [];
    }

    return collectModuleSpecifiers(sourceText)
      .filter((specifier) => patterns.some((pattern) => pattern.test(specifier)))
      .map((specifier) => `${relativeToCore(filePath)} -> ${specifier}`);
  });
}

describe("runtime/core architectural boundaries", () => {
  it("does not depend on Flutter, Dart legacy runtime, or ../venera-core from src", () => {
    const violations = findForbiddenImports("src", forbiddenLegacyPatterns);
    expect(violations).toEqual([]);
  });

  it("keeps Kysely out of src/domain and src/application", () => {
    const violations = findForbiddenImports("src/domain", [/^kysely(?:\/.*)?$/]).concat(
      findForbiddenImports("src/application", [/^kysely(?:\/.*)?$/])
    );

    expect(violations).toEqual([]);
  });

  it("keeps src/index.ts free of db row/schema exports when the entrypoint exists", () => {
    const indexSource = readCoreFile("src/index.ts");

    if (indexSource === null) {
      expect(indexSource).toBeNull();
      return;
    }

    const strippedSource = stripComments(indexSource);
    const moduleSpecifiers = collectModuleSpecifiers(strippedSource);

    const forbiddenReExports = moduleSpecifiers.filter(
      (specifier) =>
        specifier.startsWith("./db") ||
        specifier.startsWith("./repositories") ||
        specifier.includes("/schema") ||
        specifier.includes("/rows") ||
        specifier.includes("/tables")
    );

    const forbiddenPublicNames = [...strippedSource.matchAll(/\b([A-Za-z0-9_]+(?:Row|Rows|Table|Tables|Schema|Schemas))\b/g)].map(
      (match) => match[1]
    );

    expect(forbiddenReExports).toEqual([]);
    expect(forbiddenPublicNames).toEqual([]);
    expect(strippedSource).not.toMatch(/\bKysely\b/);
  });
});
