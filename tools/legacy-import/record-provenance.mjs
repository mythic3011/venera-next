// Runs ONLY inside an isolated snapshot-parser worker. Evidence describes
// the exact *already inspected* local.db snapshot, not arbitrary SQL or a
// renderer/plugin-provided record. No original titles/paths enter stdout.
import { createHash } from "node:crypto";
import { DatabaseSync } from "node:sqlite";
import { readFile } from "node:fs/promises";

const FIELDS = Object.freeze([
  "id", "comic_type", "title", "subtitle", "tags", "directory",
  "chapters", "cover", "downloadedChapters", "created_at",
]);
const LIMIT_ROWS = 100000, LIMIT_FIELD_BYTES = 64000;
const HEX64 = /^[a-f0-9]{64}$/;
function reject() { throw new Error("LEGACY_EVIDENCE_INVALID"); }
function encode(value) {
  if (value === null) return ["null"];
  if (typeof value === "string") {
    if (Buffer.byteLength(value,"utf8")>LIMIT_FIELD_BYTES) reject();
    return ["string",value];
  }
  if (typeof value === "number" && Number.isSafeInteger(value)) return ["integer",String(value)];
  if (typeof value === "bigint") return ["integer",String(value)];
  reject(); // BLOB and floating-point identities are unsupported
}
const hash = data => createHash("sha256").update(data).digest("hex");
export function digestComicRow(row) {
  if (!row || typeof row!=="object" || Array.isArray(row) ||
      FIELDS.some(field=>!Object.hasOwn(row,field))) reject();
  if (typeof row.id!=="string" || !row.id || !Number.isSafeInteger(row.comic_type) ||
      row.id.length>LIMIT_FIELD_BYTES) reject();
  const wire = JSON.stringify(["legacy-local-comic-row-v1",
    ...FIELDS.map(field=>[field,encode(row[field])])]);
  return hash(Buffer.from(wire));
}
export async function attestLocalComicsSnapshot(snapshotPath) {
  // Must be called only AFTER the same snapshot passed the l0 schema audit.
  const bytes=await readFile(snapshotPath);
  if (bytes.length>96*1024*1024 || bytes.subarray(0,16).toString("binary")!=="SQLite format 3\0")
    reject();
  const snapshotSha256=hash(bytes);
  let db;
  try {
    db=new DatabaseSync(snapshotPath,{readOnly:true});
    db.exec("PRAGMA trusted_schema=OFF; PRAGMA query_only=ON");
    const count=Number(db.prepare("SELECT COUNT(*) AS n FROM comics").get().n);
    if (!Number.isSafeInteger(count) || count>LIMIT_ROWS) reject();
    const seen=new Set(),records=[];
    const rows=db.prepare("SELECT "+FIELDS.map(n=>'"'+n+'"').join(",")+
      " FROM comics ORDER BY comic_type,id").iterate();
    for(const row of rows) {
      const key=[String(row.comic_type),row.id];
      const signature=JSON.stringify(key);
      if(seen.has(signature))reject();
      seen.add(signature);
      records.push({
        fileRole:"local.db",tableKind:"comics",
        scopeKey:"",legacyTypeKey:key[0],legacyId:key[1],
        recordDigest:digestComicRow(row)
      });
    }
    if(records.length!==count)reject();
    return {version:1,role:"local.db",snapshotSha256,records};
  } finally { db?.close(); }
}
