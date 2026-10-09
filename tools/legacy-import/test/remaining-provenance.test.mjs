import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { createHash } from "node:crypto";
import { mkdtemp, writeFile, rm, readFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { attestHistorySnapshot, attestFavoriteFoldersSnapshot,
  attestJsonSnapshot } from "../record-provenance.mjs";
import { TrustedSnapshotLeaseRegistry } from "../snapshot-lease.mjs";

const DATASET="a8c4e71d-a023-4b44-a921-a6047a95d943";
const OWNER="user-A";
const HISTORY_SQL="CREATE TABLE history(id TEXT PRIMARY KEY,title TEXT,subtitle TEXT,cover TEXT,time INT,type INT,ep INT,page INT,readEpisode TEXT,max_page INT,chapter_group INT)";
const IMAGE_SQL="CREATE TABLE image_favorites(id TEXT,title TEXT NOT NULL,sub_title TEXT,author TEXT,tags TEXT,translated_tags TEXT,time INT,max_page INT,source_key TEXT NOT NULL,image_favorites_ep TEXT NOT NULL,other TEXT NOT NULL,PRIMARY KEY(id,source_key))";
const FAV_COLS="id TEXT,name TEXT,author TEXT,type INT,tags TEXT,cover_path TEXT,time TEXT,translated_tags TEXT,display_order INT";
async function fixture(t){
 const dir=await mkdtemp(join(tmpdir(),"venera-provenance-fixture-"));
 t.after(()=>rm(dir,{recursive:true,force:true}));
 return dir;
}
function writeDb(path,ddl){const db=new DatabaseSync(path);db.exec(ddl);return db;}
function sha(bytes){return createHash("sha256").update(bytes).digest("hex");}
test("history and image favorites produce separate, stable row keys without leaking titles",async t=>{
 const dir=await fixture(t),path=join(dir,"history.db");
 const db=writeDb(path,HISTORY_SQL+";"+IMAGE_SQL);
 db.prepare("INSERT INTO history VALUES(?,?,?,?,?,?,?,?,?,?,?)")
   .run("comic42","SECRET_HISTORY_TITLE","","",1,2,3,4,"3",10,null);
 db.prepare("INSERT INTO image_favorites VALUES(?,?,?,?,?,?,?,?,?,?,?)")
   .run("image9","SECRET_IMAGE_TITLE","","","[]","[]",1,3,"ehentai","{}","{}");
 db.close();
 const first=await attestHistorySnapshot(path),next=await attestHistorySnapshot(path);
 assert.deepEqual(first,next);
 assert.equal(first.records.length,2);
 assert.deepEqual(first.records.map(r=>r.tableKind).sort(),["history","image_favorites"]);
 assert.equal(first.records[0].legacyTypeKey,"2");
 assert.equal(first.records[1].legacyTypeKey,"ehentai");
 assert.ok(!JSON.stringify(first).includes("SECRET_HISTORY_TITLE"));
 assert.ok(!JSON.stringify(first).includes("SECRET_IMAGE_TITLE"));
 const bytes=await readFile(path),lease=new TrustedSnapshotLeaseRegistry();
 const {leaseRef}=lease.issue({ownerScopeId:OWNER,datasetId:DATASET,
   inputs:[{role:"history.db",bytes}],recordProofs:[first]});
 const context={ownerScopeId:OWNER,datasetId:DATASET,leaseRef};
 const inputManifest=lease.getManifest(context);
 for(const record of first.records){
   assert.equal(lease.verifyRecord({...context,inputManifest,
     key:{datasetId:DATASET,...record},recordDigest:record.recordDigest}),true);
 }
 assert.equal(lease.verifyRecord({...context,inputManifest,
   key:{datasetId:DATASET,...first.records[0],legacyId:"fabricated"},
   recordDigest:first.records[0].recordDigest}),false);
});
test("history proof disallows duplicate compound identities from ambiguous source",async t=>{
 const dir=await fixture(t),path=join(dir,"history.db");
 const db=writeDb(path,HISTORY_SQL.replace("id TEXT PRIMARY KEY","id TEXT"));
 const ins=db.prepare("INSERT INTO history VALUES(?,?,?,?,?,?,?,?,?,?,?)");
 ins.run("dup","a","","",1,1,0,0,"",1,null);
 ins.run("dup","b","","",1,1,0,0,"",1,null);
 db.close();
 await assert.rejects(attestHistorySnapshot(path),/LEGACY_EVIDENCE_INVALID/);
});
test("dynamic quote-containing folder names are safely handled, with folder scope in key",async t=>{
 const dir=await fixture(t),path=join(dir,"local_favorite.db");
 const tricky='some"; DROP TABLE history; --';
 const quoted=tricky.replaceAll('"','""');
 const db=writeDb(path,
   'CREATE TABLE "'+quoted+'" ('+FAV_COLS+'); CREATE TABLE "Other Folder" ('+FAV_COLS+')');
 for(const folder of [tricky,"Other Folder"]){
   db.prepare('INSERT INTO "'+folder.replaceAll('"','""')+'" VALUES (?,?,?,?,?,?,?,?,?)')
     .run("same","SECRET_FAVORITE_TITLE","",1,"[]","", "2025","",0);
 }
 db.close();
 const proof=await attestFavoriteFoldersSnapshot(path);
 assert.equal(proof.records.length,2);
 assert.notEqual(proof.records[0].scopeKey,proof.records[1].scopeKey);
 assert.ok(!JSON.stringify(proof).includes("SECRET_FAVORITE_TITLE"));
 const registry=new TrustedSnapshotLeaseRegistry(),bytes=await readFile(path);
 const {leaseRef}=registry.issue({ownerScopeId:OWNER,datasetId:DATASET,
   inputs:[{role:"local_favorite.db",bytes}],recordProofs:[proof]});
 const context={ownerScopeId:OWNER,datasetId:DATASET,leaseRef};
 const inputManifest=registry.getManifest(context);
 for(const row of proof.records)
   assert.equal(registry.verifyRecord({...context,inputManifest,
     key:{datasetId:DATASET,...row},recordDigest:row.recordDigest}),true);
 assert.equal(registry.verifyRecord({...context,inputManifest,
   key:{datasetId:DATASET,...proof.records[0],scopeKey:"forged"},
   recordDigest:proof.records[0].recordDigest}),false);
});
test("same old id/type twice in the same favorite folder fails closed",async t=>{
 const dir=await fixture(t),path=join(dir,"local_favorite.db");
 const db=writeDb(path,'CREATE TABLE "Duplicates" ('+FAV_COLS+')');
 const ins=db.prepare('INSERT INTO "Duplicates" VALUES(?,?,?,?,?,?,?,?,?)');
 for(const x of [1,2])ins.run("id","title","",1,"","","","",x);
 db.close();
 await assert.rejects(attestFavoriteFoldersSnapshot(path),/LEGACY_EVIDENCE_INVALID/);
});
test("appdata attests only reviewed setting candidates, implicitData attests none",async t=>{
 const dir=await fixture(t);
 const app=join(dir,"appdata.json"),implicit=join(dir,"implicitData.json");
 await writeFile(app,JSON.stringify({settings:{
   theme_mode:"dark",enableTapToTurnPages:true,preloadImageCount:3,
   webdav:[{password:"DO_NOT_EXPORT"}],auth_token:"DO_NOT_EXPORT"
 }}));
 await writeFile(implicit,JSON.stringify({
   token:"DO_NOT_EXPORT",cookies:"DO_NOT_EXPORT",credentials:"DO_NOT_EXPORT"
 }));
 const a=await attestJsonSnapshot(app,"appdata.json");
 const b=await attestJsonSnapshot(implicit,"implicitData.json");
 assert.deepEqual(a.records.map(x=>x.legacyId).sort(),
   ["enableTapToTurnPages","preloadImageCount","theme_mode"]);
 assert.equal(b.records.length,0);
 assert.ok(!JSON.stringify([a,b]).includes("DO_NOT_EXPORT"));
 const registry=new TrustedSnapshotLeaseRegistry();
 const {leaseRef}=registry.issue({ownerScopeId:OWNER,datasetId:DATASET,
   inputs:[{role:"appdata.json",bytes:await readFile(app)},
     {role:"implicitData.json",bytes:await readFile(implicit)}],
   recordProofs:[a,b]});
 const context={ownerScopeId:OWNER,datasetId:DATASET,leaseRef};
 const inputManifest=registry.getManifest(context);
 assert.equal(registry.verifyRecord({...context,inputManifest,
   key:{datasetId:DATASET,...a.records[0]},
   recordDigest:a.records[0].recordDigest}),true);
 assert.equal(registry.verifyRecord({...context,inputManifest,
   key:{datasetId:DATASET,fileRole:"implicitData.json",
     tableKind:"implicit",scopeKey:"",legacyTypeKey:"",legacyId:"token"},
   recordDigest:"1".repeat(64)}),false);
});
test("wrong snapshot hash or unsanctioned record kind cannot extend proof list",async t=>{
 const dir=await fixture(t),path=join(dir,"appdata.json");
 await writeFile(path,'{"settings":{"theme_mode":"light"}}');
 const recordProof=await attestJsonSnapshot(path,"appdata.json");
 const bytes=await readFile(path),r=new TrustedSnapshotLeaseRegistry();
 for(const proof of [
   {...recordProof,snapshotSha256:"0".repeat(64)},
   {...recordProof,records:[...recordProof.records,
     {...recordProof.records[0],tableKind:"arbitrary"}]},
   {...recordProof,records:[...recordProof.records,
     {...recordProof.records[0]}]},
 ])assert.throws(()=>r.issue({ownerScopeId:OWNER,datasetId:DATASET,
   inputs:[{role:"appdata.json",bytes}],recordProofs:[proof]}));
});
