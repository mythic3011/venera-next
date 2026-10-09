// Venera Next L0: read-only, statistics-only inspection of five old distributed files.
// Requires Node >=22.16 for node:sqlite backup(). No old Venera runtime imports.
import { backup, DatabaseSync } from "node:sqlite";
import { createHash } from "node:crypto";
import { mkdtemp, lstat, realpath, readFile, rm, open, chmod } from "node:fs/promises";
import { join, basename } from "node:path";
import { tmpdir } from "node:os";

export const INPUT_ROLES = Object.freeze([
  "local.db", "history.db", "local_favorite.db", "appdata.json", "implicitData.json",
]);
const DB_ROLES = new Set(INPUT_ROLES.filter(x => x.endsWith(".db")));
const DENIED_TABLES = new Set([
  "source_platforms", "source_links", "reader_tabs", "reader_sessions",
  "history_events", "favorite_folders", "app_settings", "comic_titles",
  "local_library_items", "page_orders", "page_order_items", "pages",
  "chapters", "contents", "content_units",
]);
const DEFAULT_LIMITS = Object.freeze({
  maxDbBytes: 48 * 1024 * 1024,
  maxJsonBytes: 4 * 1024 * 1024,
  maxRowsPerTable: 100000,
  maxTotalRows: 250000,
  maxTables: 500,
  maxTextLength: 64000,
  maxJsonDepth: 24,
  maxJsonNodes: 100000,
});
const READER_SETTINGS = Object.freeze({
  theme_mode: x => ["system", "light", "dark"].includes(x),
  language: x => ["system", "zh-CN", "zh-TW", "en-US"].includes(x),
  enableTapToTurnPages: x => typeof x === "boolean",
  reverseTapToTurnPages: x => typeof x === "boolean",
  showPageNumberInReader: x => typeof x === "boolean",
  reverseChapterOrder: x => typeof x === "boolean",
  preloadImageCount: x => Number.isSafeInteger(x) && x >= 0 && x <= 20,
  readerScreenPicNumberForPortrait: x => Number.isSafeInteger(x) && x >= 1 && x <= 5,
  readerScreenPicNumberForLandscape: x => Number.isSafeInteger(x) && x >= 1 && x <= 5,
});
const REQUIRED = {
  "local.db": { comics: [
    "id", "title", "subtitle", "tags", "directory", "chapters", "cover",
    "comic_type", "downloadedChapters", "created_at",
  ] },
  "history.db": {
    history: ["id", "title", "subtitle", "cover", "time", "type", "ep", "page", "readEpisode", "max_page", "chapter_group"],
  },
};

export class LegacyInspectionError extends Error {
  constructor(code) { super(code); this.name = "LegacyInspectionError"; this.code = code; }
}
function fail(code) { throw new LegacyInspectionError(code); }
function sha(buffer) { return createHash("sha256").update(buffer).digest("hex"); }
function ident(name) {
  if (typeof name !== "string" || name.length > 256 || !name.length || name.includes("\0")) fail("LEGACY_SCHEMA_UNSUPPORTED");
  return '"' + name.replaceAll('"', '""') + '"';
}
function assertJsonShape(data, maxDepth, maxNodes) {
  let nodes = 0;
  const walk = (value, depth) => {
    if (++nodes > maxNodes || depth > maxDepth) fail("LEGACY_DATA_BUDGET_EXCEEDED");
    if (typeof value === "string" && value.length > DEFAULT_LIMITS.maxTextLength) fail("LEGACY_DATA_BUDGET_EXCEEDED");
    if (Array.isArray(value)) for (const item of value) walk(item, depth + 1);
    else if (value && typeof value === "object") {
      for (const [key, val] of Object.entries(value)) {
        if (["__proto__", "prototype", "constructor"].includes(key)) fail("LEGACY_JSON_UNSAFE_KEY");
        walk(val, depth + 1);
      }
    }
  };
  walk(data, 0);
}
function safeParse(text, limits) {
  let data;
  try { data = JSON.parse(text); } catch { fail("LEGACY_JSON_MALFORMED"); }
  assertJsonShape(data, limits.maxJsonDepth, limits.maxJsonNodes);
  return data;
}
function readEmbeddedJson(value, limits) {
  if (typeof value !== "string" || value.length > limits.maxTextLength) return false;
  try { safeParse(value, limits); return true; } catch { return false; }
}
function schemaTables(db, limits) {
  const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all().map(r => r.name);
  if (tables.length > limits.maxTables) fail("LEGACY_DATA_BUDGET_EXCEEDED");
  if (tables.some(t => DENIED_TABLES.has(t))) fail("LEGACY_UNIFIED_STORE_UNSUPPORTED");
  return tables;
}
function assertColumns(db, table, fields) {
  const cols = new Set(db.prepare("PRAGMA table_info(" + ident(table) + ")").all().map(r => r.name));
  if (fields.some(c => !cols.has(c))) fail("LEGACY_SCHEMA_UNSUPPORTED");
}
function boundedRows(db, table, limits) {
  const count = Number(db.prepare("SELECT COUNT(*) AS n FROM " + ident(table)).get().n);
  if (!Number.isSafeInteger(count) || count > limits.maxRowsPerTable) fail("LEGACY_DATA_BUDGET_EXCEEDED");
  return count;
}
function auditDatabase(db, role, limits) {
  db.exec("PRAGMA trusted_schema=OFF; PRAGMA query_only=ON");
  const qc = db.prepare("PRAGMA quick_check(1)").get();
  if (!qc || Object.values(qc)[0] !== "ok") fail("LEGACY_SOURCE_CORRUPT");
  const tables = schemaTables(db, limits);
  const counts = { records: 0, eligible: 0, deferred: 0, reviewRequired: 0, invalid: 0, imageFavorites: 0 };
  if (role === "local.db") {
    if (tables.length !== 1 || !tables.includes("comics")) fail("LEGACY_SCHEMA_UNSUPPORTED");
    assertColumns(db, "comics", REQUIRED[role].comics);
    boundedRows(db, "comics", limits);
    for (const row of db.prepare("SELECT id, comic_type, title, chapters, tags, downloadedChapters FROM comics").iterate()) {
      counts.records++;
      if (typeof row.id !== "string" || !Number.isSafeInteger(row.comic_type) ||
          typeof row.title !== "string" || row.title.length > limits.maxTextLength ||
          !readEmbeddedJson(row.chapters, limits) ||
          !readEmbeddedJson(row.tags, limits) ||
          !readEmbeddedJson(row.downloadedChapters, limits)) counts.invalid++;
      else counts.eligible++; // metadata candidate only, never assert image availability
    }
    counts.reviewRequired = counts.eligible; // no explicit asset-root grant or inspected pages in L0
  } else if (role === "history.db") {
    if (!tables.includes("history") || tables.some(t => !["history", "image_favorites"].includes(t))) fail("LEGACY_SCHEMA_UNSUPPORTED");
    assertColumns(db, "history", REQUIRED[role].history);
    const total = boundedRows(db, "history", limits);
    counts.records = total;
    counts.reviewRequired = total; // chapter/page ordinal is never verified in L0
    if (tables.includes("image_favorites")) {
      assertColumns(db, "image_favorites", ["id", "source_key", "image_favorites_ep", "other"]);
      counts.imageFavorites = boundedRows(db, "image_favorites", limits);
      counts.records += counts.imageFavorites;
      counts.deferred += counts.imageFavorites;
      if (counts.records > limits.maxTotalRows) fail("LEGACY_DATA_BUDGET_EXCEEDED");
    }
  } else if (role === "local_favorite.db") {
    if (tables.length === 0) fail("LEGACY_SCHEMA_UNSUPPORTED");
    for (const table of tables) {
      assertColumns(db, table, ["id", "name", "author", "type", "tags", "cover_path", "time", "display_order"]);
      const n = boundedRows(db, table, limits);
      counts.records += n;
      if (counts.records > limits.maxTotalRows) fail("LEGACY_DATA_BUDGET_EXCEEDED");
      counts.deferred += n; // requires mapped Content + M2 UserCollection
    }
    counts.folders = tables.length;
  }
  return { schemaVariant: "distributed-v1", ...counts };
}
function auditJson(value, role, limits) {
  const data = safeParse(value.toString("utf8"), limits);
  if (!data || typeof data !== "object" || Array.isArray(data)) fail("LEGACY_SCHEMA_UNSUPPORTED");
  if (role === "appdata.json") {
    if (!data.settings || typeof data.settings !== "object" || Array.isArray(data.settings)) fail("LEGACY_SCHEMA_UNSUPPORTED");
    const entries = Object.entries(data.settings);
    let candidates = 0;
    for (const [key, value] of entries) if (Object.hasOwn(READER_SETTINGS, key) && READER_SETTINGS[key](value)) candidates++;
    return { schemaVariant: "legacy-appdata", records: entries.length, eligible: candidates,
      deferred: candidates, reviewRequired: 0, invalid: 0, skipped: entries.length - candidates };
  }
  // implicitData.json is intentionally *not* mapped at L0; cannot infer trusted settings.
  return { schemaVariant: "legacy-implicit", records: Object.keys(data).length, eligible: 0,
    deferred: 0, reviewRequired: 0, invalid: 0, skipped: Object.keys(data).length };
}
async function regularInput(path, limit) {
  let st;
  try { st = await lstat(path); }
  catch (e) { if (e?.code === "ENOENT") return null; fail("LEGACY_SOURCE_UNREADABLE"); }
  if (!st.isFile() || st.isSymbolicLink()) fail("LEGACY_INPUT_NOT_ALLOWED");
  if (st.size > limit) fail("LEGACY_DATA_BUDGET_EXCEEDED");
  return st;
}
async function checkSqliteHeader(path) {
  const file = await open(path, "r");
  try {
    const buf = Buffer.alloc(16);
    const { bytesRead } = await file.read(buf, 0, 16, 0);
    if (bytesRead !== 16 || !buf.equals(Buffer.from("SQLite format 3\0"))) fail("LEGACY_SCHEMA_UNSUPPORTED");
  } finally { await file.close(); }
}

async function snapshotDatabase(source, target, limits) {
  await checkSqliteHeader(source);
  let db;
  try {
    db = new DatabaseSync(source, { readOnly: true });
    db.exec("PRAGMA trusted_schema=OFF; PRAGMA query_only=ON");
    await backup(db, target); // online SQLite-consistent snapshot (including WAL)
    const st = await lstat(target);
    if (st.size > limits.maxDbBytes * 2) fail("LEGACY_DATA_BUDGET_EXCEEDED");
    return sha(await readFile(target));
  } catch (e) {
    if (e instanceof LegacyInspectionError) throw e;
    fail("LEGACY_SNAPSHOT_UNAVAILABLE");
  } finally { db?.close(); }
}
async function inspectSnapshot(path, role, limits) {
  let db;
  try {
    db = new DatabaseSync(path, { readOnly: true });
    return auditDatabase(db, role, limits);
  } catch (e) {
    if (e instanceof LegacyInspectionError) throw e;
    fail("LEGACY_SOURCE_CORRUPT");
  } finally { db?.close(); }
}
export async function previewLegacyDirectory(userSelectedDirectory, options = {}) {
  if (typeof userSelectedDirectory !== "string" || !userSelectedDirectory) fail("LEGACY_INPUT_NOT_ALLOWED");
  const limits = { ...DEFAULT_LIMITS, ...(options.limits || {}) };
  if (Object.entries(limits).some(([k, v]) => !(k in DEFAULT_LIMITS) ||
      !Number.isSafeInteger(v) || v <= 0 || v > DEFAULT_LIMITS[k])) fail("LEGACY_LIMIT_INVALID");
  let folder;
  try { folder = await realpath(userSelectedDirectory); } catch { fail("LEGACY_INPUT_NOT_ALLOWED"); }
  const stage = await mkdtemp(join(tmpdir(), "venera-legacy-l0-"));
  await chmod(stage, 0o700);
  const files = [];
  const digests = [];
  try {
    for (const role of INPUT_ROLES) {
      const source = join(folder, role);
      let input;
      try { input = await regularInput(source, DB_ROLES.has(role) ? limits.maxDbBytes : limits.maxJsonBytes); }
      catch (e) { files.push({ role, status: "rejected", code: e?.code || "LEGACY_SOURCE_UNREADABLE" }); continue; }
      if (!input) { files.push({ role, status: "missing", code: "SKIPPED_MISSING_INPUT" }); continue; }
      try {
        const real = await realpath(source);
        if (basename(real) !== role) fail("LEGACY_INPUT_NOT_ALLOWED");
        let result, digest;
        if (DB_ROLES.has(role)) {
          const snap = join(stage, role + ".snapshot");
          digest = await snapshotDatabase(real, snap, limits);
          result = await inspectSnapshot(snap, role, limits);
        } else {
          const b = await readFile(real);
          if (b.length > limits.maxJsonBytes) fail("LEGACY_DATA_BUDGET_EXCEEDED");
          digest = sha(b);
          result = auditJson(b, role, limits);
        }
        digests.push([role, digest]);
        files.push({ role, status: "inspected", ...result });
      } catch (e) {
        files.push({ role, status: "rejected", code: e?.code || "LEGACY_SOURCE_UNREADABLE" });
      }
    }
    const totals = { inspected: 0, missing: 0, rejected: 0, records: 0, eligible: 0, deferred: 0, reviewRequired: 0 };
    for (const f of files) {
      totals[f.status]++;
      for (const k of ["records", "eligible", "deferred", "reviewRequired"]) totals[k] += f[k] || 0;
    }
    // Internal-only plan evidence. No path, titles, cookies, raw input or hash in public report.
    const planDigest = sha(Buffer.from(JSON.stringify(digests)));
    return {
      status: totals.rejected ? "needs_attention" : totals.inspected ? "preview_only" : "no_inputs",
      scope: "old-venera-five-distributed-files",
      readOnly: true,
      canCommit: false,
      phase: "L0",
      totals,
      files,
      ...(options.includePrivatePlanDigest === true ? { planDigest } : {}),
    };
  } finally {
    await rm(stage, { recursive: true, force: true }); // only app-owned private snapshot directory
  }
}
