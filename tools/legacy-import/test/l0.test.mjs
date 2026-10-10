import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { mkdtemp, writeFile, rm, symlink, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { previewLegacyDirectory, INPUT_ROLES } from "../l0.mjs";

const LOCAL_SCHEMA = [
  "CREATE TABLE comics (id TEXT NOT NULL, title TEXT NOT NULL, subtitle TEXT NOT NULL,",
  "tags TEXT NOT NULL, directory TEXT NOT NULL, chapters TEXT NOT NULL, cover TEXT NOT NULL,",
  "comic_type INTEGER NOT NULL, downloadedChapters TEXT NOT NULL, created_at INTEGER, PRIMARY KEY (id,comic_type))",
].join(" ");
const HISTORY_SCHEMA = [
  "CREATE TABLE history (id TEXT PRIMARY KEY,title TEXT,subtitle TEXT,cover TEXT,time INT,",
  "type INT,ep INT,page INT,readEpisode TEXT,max_page INT,chapter_group INT)",
].join(" ");
const IMAGE_SCHEMA = [
  "CREATE TABLE image_favorites (id TEXT,title TEXT NOT NULL,sub_title TEXT,author TEXT,tags TEXT,",
  "translated_tags TEXT,time INT,max_page INT,source_key TEXT NOT NULL,",
  "image_favorites_ep TEXT NOT NULL,other TEXT NOT NULL,PRIMARY KEY(id,source_key))",
].join(" ");
const FAV_SCHEMA = "id TEXT, name TEXT, author TEXT, type INT, tags TEXT, cover_path TEXT, " +
                   "time TEXT, translated_tags TEXT, display_order INT";

async function fixture(t) {
  const dir = await mkdtemp(join(tmpdir(), "venera-legacy-l0-test-"));
  t.after(async () => rm(dir, { force: true, recursive: true }));
  return dir;
}
function sqlite(path, sql) {
  const db = new DatabaseSync(path);
  db.exec(sql);
  return db;
}
function insertLocal(db, id = "c1") {
  db.prepare(
    "INSERT INTO comics VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  ).run(id,"Sample Title","","[]","unused","{}","",1,"[]",1700000000000);
}

test("L0: exact five-file registry, no fallback to unified store", async t => {
  assert.deepEqual(INPUT_ROLES, ["local.db","history.db","local_favorite.db","appdata.json","implicitData.json"]);
  const dir = await fixture(t);
  const unified = sqlite(join(dir,"venera.db"),"CREATE TABLE contents(id TEXT PRIMARY KEY)");
  unified.close();
  const empty = await previewLegacyDirectory(dir);
  assert.equal(empty.status, "no_inputs");
  assert.equal(empty.totals.missing, 5);
  assert.equal(empty.canCommit, false);
  assert.ok(!JSON.stringify(empty).includes(dir));
});

test("L0: five real distributed inputs emit counts only, separate image favorites", async t => {
  const dir = await fixture(t);
  const local = sqlite(join(dir,"local.db"), LOCAL_SCHEMA);
  insertLocal(local);
  local.close();
  const history = sqlite(join(dir,"history.db"),HISTORY_SCHEMA+";"+IMAGE_SCHEMA);
  history.prepare("INSERT INTO history VALUES (?,?,?,?,?,?,?,?,?,?,?)").run("c1","Top-secret reader title","","",1,1,2,3,"3",5,null);
  history.prepare("INSERT INTO image_favorites (id,title,source_key,image_favorites_ep,other) VALUES(?,?,?,?,?)")
    .run("image1","Private fav","comics","{}", "{}");
  history.close();
  const fav = sqlite(join(dir,"local_favorite.db"),
    'CREATE TABLE "Favorites" (' + FAV_SCHEMA + ')');
  fav.prepare('INSERT INTO "Favorites" VALUES (?,?,?,?,?,?,?,?,?)')
    .run("c1","Favourite sensitive title","",1,"","","", "", 0);
  fav.close();
  await writeFile(join(dir,"appdata.json"),JSON.stringify({
    settings:{ theme_mode:"dark", preloadImageCount:3, webdav:[{ password:"secret" }],
      auth_token:"secret",enableTapToTurnPages:true, randomSetting:42 },
    searchHistory:["private query"],
  }));
  await writeFile(join(dir,"implicitData.json"),JSON.stringify({
    password:"secret", token:"secret", scripts:["untrusted js"]
  }));
  const result=await previewLegacyDirectory(dir);
  assert.equal(result.status,"preview_only");
  assert.equal(result.totals.inspected,5);
  assert.equal(result.totals.eligible,4); // 1 local + 3 safe pref candidates
  const hist=result.files.find(x=>x.role==="history.db");
  assert.equal(hist.records,2);
  assert.equal(hist.reviewRequired,1);
  assert.equal(hist.imageFavorites,1);
  assert.equal(hist.deferred,1);
  const prefs=result.files.find(x=>x.role==="appdata.json");
  assert.equal(prefs.skipped,3);
  const implicit=result.files.find(x=>x.role==="implicitData.json");
  assert.equal(implicit.eligible,0);
  assert.equal(implicit.skipped,3);
  const text=JSON.stringify(result);
  for(const secret of ["Top-secret reader title","Favourite sensitive title","private query","secret",dir])
    assert.ok(!text.includes(secret));
  assert.equal(result.canCommit,false);
});

test("L0: SQLite backup sees committed WAL changes, does not write to original DB", async t => {
  const dir=await fixture(t);
  const file=join(dir,"local.db");
  const db=sqlite(file, "PRAGMA journal_mode=WAL;"+LOCAL_SCHEMA);
  insertLocal(db,"from-wal");
  const before=await stat(file);
  try {
    const out=await previewLegacyDirectory(dir);
    assert.equal(out.files[0].eligible,1);
    const after=await stat(file);
    assert.equal(after.size,before.size);
    assert.equal(after.mtimeMs,before.mtimeMs);
  } finally { db.close(); }
});

test("L0: renamed Unified Store cannot masquerade as local.db", async t => {
  const dir=await fixture(t);
  const db=sqlite(join(dir,"local.db"),
    "CREATE TABLE contents(id TEXT PRIMARY KEY); CREATE TABLE pages(id TEXT);");
  db.close();
  const out=await previewLegacyDirectory(dir);
  assert.equal(out.files[0].status,"rejected");
  assert.equal(out.files[0].code,"LEGACY_UNIFIED_STORE_UNSUPPORTED");
});

test("L0: folder table names are quoted as identifiers, never executed as SQL", async t => {
  const dir=await fixture(t);
  const folder='quotes"; DROP TABLE comics; --';
  const quoted=folder.replaceAll('"','""');
  const db=sqlite(join(dir,"local_favorite.db"),'CREATE TABLE "'+quoted+'" ('+FAV_SCHEMA+')');
  db.prepare('INSERT INTO "'+quoted+'" VALUES (?,?,?,?,?,?,?,?,?)').run("item","title","",2,"","","","",1);
  db.close();
  const out=await previewLegacyDirectory(dir);
  const fav=out.files[2];
  assert.equal(fav.status,"inspected");
  assert.equal(fav.folders,1);
  assert.equal(fav.deferred,1);
  assert.ok(!JSON.stringify(out).includes(folder));
});

test("L0: symlink and malformed file are denied, no implicit source writes", async t => {
  const dir=await fixture(t);
  const external=join(dir,"external.db");
  const db=sqlite(external,LOCAL_SCHEMA);db.close();
  await symlink(external,join(dir,"local.db"));
  await writeFile(join(dir,"appdata.json"),"not-json");
  const out=await previewLegacyDirectory(dir);
  assert.equal(out.files[0].code,"LEGACY_INPUT_NOT_ALLOWED");
  assert.equal(out.files[3].code,"LEGACY_JSON_MALFORMED");
  assert.equal(out.totals.rejected,2);
  assert.equal(out.status,"needs_attention");
});

test("L0: dangerous JSON keys, unsupported schema and bounded JSON reject safely", async t => {
  const dir=await fixture(t);
  await writeFile(join(dir,"implicitData.json"),'{"__proto__":{"a":1}}');
  let out=await previewLegacyDirectory(dir);
  assert.equal(out.files[4].code,"LEGACY_JSON_UNSAFE_KEY");
  await writeFile(join(dir,"implicitData.json"),'{"a":{"b":{"c":1}}}');
  out=await previewLegacyDirectory(dir,{ limits:{maxJsonDepth:2} });
  assert.equal(out.files[4].code,"LEGACY_DATA_BUDGET_EXCEEDED");
  await writeFile(join(dir,"appdata.json"),JSON.stringify({ settings:[] }));
  out=await previewLegacyDirectory(dir);
  assert.equal(out.files[3].code,"LEGACY_SCHEMA_UNSUPPORTED");
});

test("L0: row budgets enforced before DB iteration; changed settings never create IDs",async t=>{
 const dir=await fixture(t);
 const local=sqlite(join(dir,"local.db"),LOCAL_SCHEMA);
 insertLocal(local,"c1");insertLocal(local,"c2");local.close();
 let out=await previewLegacyDirectory(dir,{limits:{maxRowsPerTable:1}});
 assert.equal(out.files[0].code,"LEGACY_DATA_BUDGET_EXCEEDED");
 out=await previewLegacyDirectory(dir);
 assert.equal(out.files[0].eligible,2);
 await writeFile(join(dir,"appdata.json"),JSON.stringify({settings:{language:"zh-TW"}}));
 const next=await previewLegacyDirectory(dir);
 assert.equal(next.files[0].eligible,2);
 assert.equal(next.files[3].deferred,1);
 assert.equal(next.canCommit,false);
});

test("L0: cross-folder aggregate row cap applies to dynamic favorite tables", async t => {
  const dir=await fixture(t);
  const db=sqlite(join(dir,"local_favorite.db"),
    'CREATE TABLE "Folder A" (' + FAV_SCHEMA + '); CREATE TABLE "Folder B" (' + FAV_SCHEMA + ')');
  for(const folder of ["Folder A","Folder B"]){
    db.prepare('INSERT INTO "'+folder+'" VALUES (?,?,?,?,?,?,?,?,?)')
      .run("id", "title", "", 1, "", "", "", "", 0);
  }
  db.close();
  const out=await previewLegacyDirectory(dir, {limits:{maxTotalRows:1}});
  assert.equal(out.files[2].status, "rejected");
  assert.equal(out.files[2].code, "LEGACY_DATA_BUDGET_EXCEEDED");
});

test("L0: local embedded JSON must have known shapes, malformed UTF-8 is rejected", async t => {
  const dir=await fixture(t);
  const db=sqlite(join(dir,"local.db"),LOCAL_SCHEMA);
  db.prepare("INSERT INTO comics VALUES (?,?,?,?,?,?,?,?,?,?)")
    .run("bad","Title","","{}", "dir", "[]", "", 1, "{}", 1);
  db.close();
  await writeFile(join(dir,"implicitData.json"),Buffer.from([0x7b,0xff,0x7d]));
  const out=await previewLegacyDirectory(dir);
  assert.equal(out.files[0].status,"inspected");
  assert.equal(out.files[0].eligible,0);
  assert.equal(out.files[0].invalid,1);
  assert.equal(out.files[4].code,"LEGACY_JSON_INVALID_UTF8");
});
