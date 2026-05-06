import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const supportDir = dirname(fileURLToPath(import.meta.url));

export const corePackageRoot = resolve(supportDir, "..", "..");

function walkTypeScriptFiles(absoluteDir: string): string[] {
  if (!existsSync(absoluteDir)) {
    return [];
  }

  return readdirSync(absoluteDir, { withFileTypes: true })
    .flatMap((entry) => {
      const absolutePath = resolve(absoluteDir, entry.name);

      if (entry.isDirectory()) {
        return walkTypeScriptFiles(absolutePath);
      }

      return entry.isFile() && absolutePath.endsWith(".ts") ? [absolutePath] : [];
    })
    .sort((left, right) => left.localeCompare(right));
}

export function listTypeScriptFiles(relativeDir: string): string[] {
  return walkTypeScriptFiles(resolve(corePackageRoot, relativeDir));
}

export function readCoreFile(relativePath: string): string | null {
  const absolutePath = resolve(corePackageRoot, relativePath);
  if (!existsSync(absolutePath)) {
    return null;
  }

  return readFileSync(absolutePath, "utf8");
}

export function relativeToCore(absolutePath: string): string {
  return relative(corePackageRoot, absolutePath).replaceAll("\\", "/");
}

export function stripComments(sourceText: string): string {
  return sourceText
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/\/\/.*$/gm, "");
}

export function collectModuleSpecifiers(sourceText: string): string[] {
  const moduleSpecifiers = new Set<string>();

  const fromPattern = /\b(?:import|export)\b[\s\S]*?\bfrom\s*["']([^"']+)["']/g;
  const sideEffectPattern = /\bimport\s*["']([^"']+)["']/g;
  const dynamicImportPattern = /\bimport\s*\(\s*["']([^"']+)["']\s*\)/g;

  for (const pattern of [fromPattern, sideEffectPattern, dynamicImportPattern]) {
    for (const match of sourceText.matchAll(pattern)) {
      const specifier = match[1];
      if (specifier) {
        moduleSpecifiers.add(specifier);
      }
    }
  }

  return [...moduleSpecifiers].sort((left, right) => left.localeCompare(right));
}
