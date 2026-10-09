// Runs ONLY inside an isolated snapshot-parser worker. Evidence describes
// the exact *already inspected* local.db snapshot, not arbitrary SQL or a
// renderer/plugin-provided record. No original titles/paths enter stdout.
import { createHash } from "node:crypto";
import { DatabaseSync } from "node:sqlite";
import { readFile } from "node:fs/promises";
import { READER_SETTINGS } from "./l0.mjs";

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
  if (typeof value === "boolean") return ["boolean",value];
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


// The following four proof adapters do NOT claim any data has been imported.
// They only attest exact old records in a previously validated private snapshot.
// Every proof is bound to the snapshot byte hash; private field values never
// leave the isolated worker. Do not run this module against arbitrary paths
// through a renderer, plugin RPC or an unrestricted host file picker.
const HISTORY_FIELDS = Object.freeze([
  "id","title","subtitle","cover","time","type","ep","page",
  "readEpisode","max_page","chapter_group"
]);
const IMAGE_FAV_FIELDS = Object.freeze([
  "id","title","sub_title","author","tags","translated_tags","time",
  "max_page","source_key","image_favorites_ep","other"
]);
const FAV_REQUIRED = Object.freeze([
  "id","name","author","type","tags","cover_path","time","display_order"
]);
const FAV_OPTIONAL = new Set(["translated_tags","last_update_time"]);
const MAX_TOTAL_ROWS=250000;
function tableIdent(value) {
  if(typeof value!=="string" || !value.length || value.length>256 ||
     value.includes("\0"))reject();
  return '"'+value.replaceAll('"','""')+'"';
}
function columns(db,table) {
  return db.prepare("PRAGMA table_info("+tableIdent(table)+")").all().map(x=>x.name);
}
function checkColumns(db,table,required,allowed=required) {
  const cols=columns(db,table);
  if(required.some(x=>!cols.includes(x)) ||
     cols.some(x=>!allowed.includes(x)))reject();
  return cols;
}
function tables(db) {
  const ts=db.prepare(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
  ).all().map(x=>x.name);
  if(ts.length>500)reject();
  return ts;
}
function rowDigest(role,kind,row,fields) {
  if(fields.some(x=>!Object.hasOwn(row,x)))reject();
  return hash(Buffer.from(JSON.stringify([
    "venera-legacy-record-v1",role,kind,
    ...fields.map(k=>[k,encode(row[k])])
  ])));
}
function addRecord(records,keys,record) {
  const identity=JSON.stringify([
    record.fileRole,record.tableKind,record.scopeKey,
    record.legacyTypeKey,record.legacyId
  ]);
  if(keys.has(identity))reject();
  keys.add(identity);
  records.push(record);
  if(records.length>MAX_TOTAL_ROWS)reject();
}
async function inspectSqliteProof(path,role,run) {
  const bytes=await readFile(path);
  if(bytes.length>96*1024*1024 ||
     bytes.subarray(0,16).toString("binary")!=="SQLite format 3\0")reject();
  const snapshotSha256=hash(bytes);
  let db;
  try {
    db=new DatabaseSync(path,{readOnly:true});
    db.exec("PRAGMA trusted_schema=OFF; PRAGMA query_only=ON");
    const records=run(db);
    return {version:1,role,snapshotSha256,records};
  }finally{db?.close();}
}
function assertKeyId(id) {
  if(typeof id!=="string" || !id.length ||
     Buffer.byteLength(id,"utf8")>4096 || id.includes("\0"))reject();
  return id;
}
function intKey(value) {
  if(!Number.isSafeInteger(value))reject();
  return String(value);
}
export async function attestHistorySnapshot(snapshotPath) {
  return inspectSqliteProof(snapshotPath,"history.db",db=>{
    const found=tables(db);
    if(!found.includes("history") ||
       found.some(x=>!["history","image_favorites"].includes(x)))reject();
    checkColumns(db,"history",HISTORY_FIELDS);
    const records=[],seen=new Set();
    for(const row of db.prepare(
      "SELECT "+HISTORY_FIELDS.map(tableIdent).join(",")+" FROM history"
    ).iterate()){
      const legacyId=assertKeyId(row.id),legacyTypeKey=intKey(row.type);
      addRecord(records,seen,{fileRole:"history.db",tableKind:"history",
        scopeKey:"",legacyTypeKey,legacyId,
        recordDigest:rowDigest("history.db","history",row,HISTORY_FIELDS)});
    }
    if(found.includes("image_favorites")){
      checkColumns(db,"image_favorites",IMAGE_FAV_FIELDS);
      for(const row of db.prepare(
        "SELECT "+IMAGE_FAV_FIELDS.map(tableIdent).join(",")+" FROM image_favorites"
      ).iterate()){
        const legacyId=assertKeyId(row.id);
        const legacyTypeKey=assertKeyId(row.source_key);
        addRecord(records,seen,{fileRole:"history.db",tableKind:"image_favorites",
          scopeKey:"",legacyTypeKey,legacyId,
          recordDigest:rowDigest("history.db","image_favorites",row,IMAGE_FAV_FIELDS)});
      }
    }
    return records;
  });
}
export async function attestFavoriteFoldersSnapshot(snapshotPath) {
  return inspectSqliteProof(snapshotPath,"local_favorite.db",db=>{
    const folders=tables(db);
    if(!folders.length)reject();
    const records=[],seen=new Set();
    for(const folder of folders){
      const fields=columns(db,folder);
      if(FAV_REQUIRED.some(x=>!fields.includes(x)) ||
         fields.some(x=>!FAV_REQUIRED.includes(x)&&!FAV_OPTIONAL.has(x)))reject();
      const query="SELECT "+fields.map(tableIdent).join(",")+
        " FROM "+tableIdent(folder);
      for(const row of db.prepare(query).iterate()){
        const legacyId=assertKeyId(row.id),legacyTypeKey=intKey(row.type);
        addRecord(records,seen,{
          fileRole:"local_favorite.db",tableKind:"folder_item",
          scopeKey:folder,legacyTypeKey,legacyId,
          recordDigest:rowDigest("local_favorite.db","folder_item",row,fields)
        });
      }
    }
    return records;
  });
}
export async function attestJsonSnapshot(snapshotPath,role) {
  if(!["appdata.json","implicitData.json"].includes(role))reject();
  const bytes=await readFile(snapshotPath);
  if(bytes.length>4*1024*1024)reject();
  const snapshotSha256=hash(bytes);
  let data;
  try {
    const json=new TextDecoder("utf-8",{fatal:true}).decode(bytes);
    data=JSON.parse(json);
  }catch{reject();}
  if(!data || typeof data!=="object" || Array.isArray(data))reject();
  // implicitData remains intentionally 100% NOT MAPPABLE (may hold secrets).
  if(role==="implicitData.json")
    return {version:1,role,snapshotSha256,records:[]};
  if(!data.settings || typeof data.settings!=="object" ||
     Array.isArray(data.settings))reject();
  const records=[];
  for(const [key,value]of Object.entries(data.settings)){
    if(!Object.hasOwn(READER_SETTINGS,key) || !READER_SETTINGS[key](value))continue;
    records.push({fileRole:role,tableKind:"settings",scopeKey:"",
      legacyTypeKey:"",legacyId:key,
      recordDigest:hash(Buffer.from(JSON.stringify([
        "venera-legacy-setting-v1",key,encode(value)
      ])))});
  }
  return {version:1,role,snapshotSha256,records};
}
