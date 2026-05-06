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

const forbiddenDataAccessImports = [
  /^kysely(?:\/.*)?$/,
  /^better-sqlite3$/,
  /^node:sqlite(?:\/.*)?$/,
  /(?:^|\/)\.\.\/db(?:\/|$)/,
  /(?:^|\/)\.\.\/repositories(?:\/|$)/,
  /(?:^|\/)\.\.\/legacy(?:\/|$)/,
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

  it("keeps db adapters, schema wiring, and legacy imports out of src/domain, src/application, and src/ports", () => {
    const violations = [
      ...findForbiddenImports("src/domain", forbiddenDataAccessImports),
      ...findForbiddenImports("src/application", forbiddenDataAccessImports),
      ...findForbiddenImports("src/ports", forbiddenDataAccessImports),
    ];

    expect(violations).toEqual([]);
  });

  it("keeps src/index.ts free of db, repository adapter, and schema internals when the entrypoint exists", () => {
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
        specifier.includes("/sqlite") ||
        specifier.includes("/schema") ||
        specifier.includes("/rows") ||
        specifier.includes("/tables")
    );

    const forbiddenPublicNames = [...strippedSource.matchAll(/\b([A-Za-z0-9_]+(?:Row|Rows|Table|Tables|Schema|Schemas))\b/g)].map(
      (match) => match[1]
    );

    expect(forbiddenReExports).toEqual([]);
    expect(forbiddenPublicNames).toEqual([]);
    expect(strippedSource).not.toMatch(/\bcreateCoreDatabase\b/);
    expect(strippedSource).not.toMatch(/\bKysely\b/);
  });
});
