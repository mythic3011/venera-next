import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

import ts from "typescript";

export interface BoundaryRule {
  readonly name: string;
  readonly from: readonly RegExp[];
  readonly forbidden: readonly RegExp[];
}

export interface BoundaryConfig {
  readonly files: readonly string[];
  readonly rules: readonly BoundaryRule[];
}

export interface BoundaryViolation {
  readonly file: string;
  readonly importSource: string;
  readonly rule: string;
  readonly type: "forbidden_import" | "unanalyzable_dynamic_import";
}

export async function loadBoundaryConfig(
  configPath = resolve(process.cwd(), "boundary.config.ts"),
): Promise<BoundaryConfig> {
  const module = await import(pathToFileURL(configPath).href) as {
    default: BoundaryConfig;
  };

  return module.default;
}

export async function scanBoundaries(
  config: BoundaryConfig,
  rootDirectory = process.cwd(),
): Promise<readonly BoundaryViolation[]> {
  const files = ts.sys.readDirectory(
    rootDirectory,
    [".ts", ".tsx"],
    undefined,
    [...config.files],
  );

  const violations: BoundaryViolation[] = [];
  for (const filePath of files) {
    const relativeFilePath = normalizePath(
      ts.sys.resolvePath(filePath).replace(`${normalizePath(rootDirectory)}/`, ""),
    );
    const sourceText = await readFile(filePath, "utf8");
    const sourceFile = ts.createSourceFile(
      filePath,
      sourceText,
      ts.ScriptTarget.Latest,
      true,
      filePath.endsWith(".tsx") ? ts.ScriptKind.TSX : ts.ScriptKind.TS,
    );

    const collectedImports = collectImports(sourceFile, filePath);
    for (const collectedImport of collectedImports) {
      if (collectedImport.type === "unanalyzable_dynamic_import") {
        violations.push({
          file: relativeFilePath,
          importSource: "<dynamic>",
          rule: "dynamic-import-literal-only",
          type: "unanalyzable_dynamic_import",
        });
        continue;
      }

      const target = resolveImportTarget(
        rootDirectory,
        filePath,
        collectedImport.specifier,
      );
      const normalizedTarget = normalizePath(target);
      for (const rule of config.rules) {
        if (!rule.from.some((pattern) => pattern.test(relativeFilePath))) {
          continue;
        }

        if (rule.forbidden.some((pattern) => pattern.test(normalizedTarget))) {
          violations.push({
            file: relativeFilePath,
            importSource: normalizedTarget,
            rule: rule.name,
            type: "forbidden_import",
          });
        }
      }
    }
  }

  return violations;
}

interface LiteralImportReference {
  readonly specifier: string;
  readonly type: "literal_import";
}

interface UnanalyzableDynamicImportReference {
  readonly type: "unanalyzable_dynamic_import";
}

type CollectedImport = LiteralImportReference | UnanalyzableDynamicImportReference;

function collectImports(
  sourceFile: ts.SourceFile,
  filePath: string,
): readonly CollectedImport[] {
  const imports: CollectedImport[] = [];

  function visit(node: ts.Node): void {
    if (
      ts.isImportDeclaration(node)
      && ts.isStringLiteral(node.moduleSpecifier)
    ) {
      imports.push({
        type: "literal_import",
        specifier: node.moduleSpecifier.text,
      });
    }

    if (
      ts.isExportDeclaration(node)
      && node.moduleSpecifier !== undefined
      && ts.isStringLiteral(node.moduleSpecifier)
    ) {
      imports.push({
        type: "literal_import",
        specifier: node.moduleSpecifier.text,
      });
    }

    if (ts.isImportTypeNode(node) && ts.isLiteralTypeNode(node.argument)) {
      const literal = node.argument.literal;
      if (ts.isStringLiteral(literal)) {
        imports.push({
          type: "literal_import",
          specifier: literal.text,
        });
      }
    }

    if (
      ts.isCallExpression(node)
      && node.expression.kind === ts.SyntaxKind.ImportKeyword
    ) {
      const [argument] = node.arguments;
      if (
        argument !== undefined
        && (ts.isStringLiteral(argument) || ts.isNoSubstitutionTemplateLiteral(argument))
      ) {
        imports.push({
          type: "literal_import",
          specifier: argument.text,
        });
      } else {
        imports.push({
          type: "unanalyzable_dynamic_import",
        });
      }
    }

    ts.forEachChild(node, visit);
  }

  visit(sourceFile);
  return imports;
}

function normalizePath(path: string): string {
  return path.replaceAll("\\", "/");
}

function resolveImportTarget(
  rootDirectory: string,
  filePath: string,
  specifier: string,
): string {
  if (specifier.startsWith("@venera/")) {
    return specifier;
  }

  if (!specifier.startsWith(".")) {
    return `external:${specifier}`;
  }

  const resolvedPath = ts.resolveModuleName(
    specifier,
    filePath,
    {
      module: ts.ModuleKind.NodeNext,
      moduleResolution: ts.ModuleResolutionKind.NodeNext,
    },
    ts.sys,
  );
  const resolvedFileName = resolvedPath.resolvedModule?.resolvedFileName;
  if (resolvedFileName === undefined) {
    return specifier;
  }

  return normalizePath(
    ts.sys.resolvePath(resolvedFileName).replace(`${normalizePath(rootDirectory)}/`, ""),
  );
}

async function main(): Promise<void> {
  const config = await loadBoundaryConfig();
  const violations = await scanBoundaries(config);

  if (violations.length === 0) {
    console.log("Boundary scan passed.");
    return;
  }

  for (const violation of violations) {
    console.error(`${violation.type}: ${violation.rule} ${violation.file} -> ${violation.importSource}`);
  }
  process.exitCode = 1;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  void main();
}
