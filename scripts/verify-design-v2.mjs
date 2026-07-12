import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const designDir = path.join(rootDir, "docs", "design", "v2");

const schemaAuthority = path.join(designDir, "02_DATABASE_SCHEMA.md");
const eventCatalog = path.join(designDir, "04_PACKAGES_AND_PIECES.md");
const observabilityCatalog = path.join(designDir, "09_OBSERVABILITY.md");
const targetFragmentFiles = [
  path.join(designDir, "05_PLUGIN_SYSTEM.md"),
  path.join(designDir, "07_FEATURES.md"),
];

function relative(filePath) {
  return path.relative(rootDir, filePath);
}

function readText(filePath) {
  return readFileSync(filePath, "utf8");
}

function extractCreateTables(filePath) {
  const lines = readText(filePath).split(/\r?\n/);
  const tables = [];

  for (const [index, line] of lines.entries()) {
    const match = line.match(/\bCREATE\s+TABLE\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/i);
    if (match) {
      tables.push({
        tableName: match[1],
        filePath,
        lineNumber: index + 1,
      });
    }
  }

  return tables;
}

function formatLocation(entry) {
  return `${relative(entry.filePath)}:${entry.lineNumber}`;
}

function extractDeclaredEventNames(filePath) {
  const lines = readText(filePath).split(/\r?\n/);
  const events = [];
  let inEventBlock = false;

  for (const [index, line] of lines.entries()) {
    if (/^\s*export\s+const\s+[A-Za-z]+Events\s*=\s*\{/.test(line)) {
      inEventBlock = true;
    }

    if (inEventBlock) {
      const matches = line.matchAll(/"([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)"/g);
      for (const match of matches) {
        events.push({
          eventName: match[1],
          filePath,
          lineNumber: index + 1,
        });
      }
    }

    if (inEventBlock && /^\s*\}\s+as\s+const\b/.test(line)) {
      inEventBlock = false;
    }
  }

  return events;
}

function extractObservedEventHeadings(filePath) {
  const lines = readText(filePath).split(/\r?\n/);
  const headings = [];

  for (const [index, line] of lines.entries()) {
    const match = line.match(/^####\s+([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)\s*$/);
    if (match) {
      headings.push({
        eventName: match[1],
        filePath,
        lineNumber: index + 1,
      });
    }
  }

  return headings;
}

function verifySchemaAuthority(errors) {
  const canonicalTables = new Map();

  for (const entry of extractCreateTables(schemaAuthority)) {
    const existing = canonicalTables.get(entry.tableName);
    if (existing) {
      errors.push(
        `Canonical schema defines table '${entry.tableName}' more than once: ${formatLocation(existing)} and ${formatLocation(entry)}.`,
      );
    } else {
      canonicalTables.set(entry.tableName, entry);
    }
  }

  const fragmentTables = new Map();

  for (const filePath of targetFragmentFiles) {
    const text = readText(filePath);
    if (!text.includes("Target fragments")) {
      errors.push(`${relative(filePath)} contains target schema fragments but is missing the Target fragments banner.`);
    }

    for (const entry of extractCreateTables(filePath)) {
      const canonical = canonicalTables.get(entry.tableName);
      if (canonical) {
        errors.push(
          `Target fragment redefines canonical table '${entry.tableName}': ${formatLocation(entry)} duplicates ${formatLocation(canonical)}.`,
        );
      }

      const priorFragment = fragmentTables.get(entry.tableName);
      if (priorFragment) {
        errors.push(
          `Target fragments define table '${entry.tableName}' more than once: ${formatLocation(priorFragment)} and ${formatLocation(entry)}.`,
        );
      } else {
        fragmentTables.set(entry.tableName, entry);
      }
    }
  }

  return {
    canonicalTableCount: canonicalTables.size,
    targetFragmentCount: fragmentTables.size,
  };
}

function verifyEventCatalog(errors) {
  const declaredEvents = new Map();
  for (const entry of extractDeclaredEventNames(eventCatalog)) {
    const existing = declaredEvents.get(entry.eventName);
    if (existing) {
      errors.push(
        `Event '${entry.eventName}' is declared more than once in 04: ${formatLocation(existing)} and ${formatLocation(entry)}.`,
      );
    } else {
      declaredEvents.set(entry.eventName, entry);
    }
  }

  const observedEvents = new Map();
  for (const entry of extractObservedEventHeadings(observabilityCatalog)) {
    const existing = observedEvents.get(entry.eventName);
    if (existing) {
      errors.push(
        `Event '${entry.eventName}' is documented more than once in 09: ${formatLocation(existing)} and ${formatLocation(entry)}.`,
      );
    } else {
      observedEvents.set(entry.eventName, entry);
    }
  }

  for (const [eventName, entry] of declaredEvents) {
    if (!observedEvents.has(eventName)) {
      errors.push(
        `Declared event '${eventName}' at ${formatLocation(entry)} has no matching 09_OBSERVABILITY.md event heading.`,
      );
    }
  }

  return {
    declaredEventCount: declaredEvents.size,
    observedEventCount: observedEvents.size,
  };
}

function main() {
  const errors = [];
  const schemaResult = verifySchemaAuthority(errors);
  const eventResult = verifyEventCatalog(errors);

  if (errors.length > 0) {
    console.error("Design v2 verification failed:");
    for (const error of errors) {
      console.error(`- ${error}`);
    }
    process.exitCode = 1;
    return;
  }

  console.log(
    [
      "Design v2 verification passed:",
      `${schemaResult.canonicalTableCount} canonical tables`,
      `${schemaResult.targetFragmentCount} target fragments`,
      `${eventResult.declaredEventCount} declared event constants`,
      `${eventResult.observedEventCount} observability event headings`,
    ].join(" "),
  );
}

main();
