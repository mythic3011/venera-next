import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { mkdtemp,rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { attestLocalComicsSnapshot, digestComicRow } from "../record-provenance.mjs";

const SQL="CREATE TABLE comics(id TEXT, title TEXT, subtitle TEXT, tags TEXT, directory TEXT, chapters TEXT, cover TEXT, comic_type INT, downloadedChapters TEXT, created_at INT)";
async function dbFixture(t) {
 const dir=await mkdtemp(join(tmpdir(),"venera-record-proof-test-"));
 t.after(async()=>rm(dir,{recursive:true,force:true}));
 const path=join(dir,"local.db"),db=new DatabaseSync(path);
 db.exec(SQL);
 return {path,db};
}
test("actual SQLite rows produce deterministic private record digests",async t=>{
 const {path,db}=await dbFixture(t);
 db.prepare("INSERT INTO comics VALUES(?,?,?,?,?,?,?,?,?,?)")
 .run("comic42","PrivateTitle","Sub","[]","/private","{}","",1,"[]",1740000000);
 db.close();
 const a=await attestLocalComicsSnapshot(path);
 const b=await attestLocalComicsSnapshot(path);
 assert.deepEqual(a,b);
 assert.equal(a.role,"local.db");
 assert.equal(a.records.length,1);
 assert.equal(a.records[0].legacyId,"comic42");
 assert.equal(a.records[0].legacyTypeKey,"1");
 assert.match(a.records[0].recordDigest,/^[0-9a-f]{64}$/);
 assert.ok(!JSON.stringify(a).includes("PrivateTitle"));
 assert.ok(!JSON.stringify(a).includes("/private"));
});
test("changing private title changes digest but does not change identity fields",async t=>{
 const {path,db}=await dbFixture(t);
 db.prepare("INSERT INTO comics VALUES(?,?,?,?,?,?,?,?,?,?)")
 .run("same","A","","[]","d","{}","",1,"[]",1);
 const before=await attestLocalComicsSnapshot(path);
 db.prepare("UPDATE comics SET title='B' WHERE id='same'").run();
 const after=await attestLocalComicsSnapshot(path);
 assert.equal(before.records[0].legacyId,after.records[0].legacyId);
 assert.notEqual(before.records[0].recordDigest,after.records[0].recordDigest);
 db.close();
});
test("type-aware digest rejects different values and arbitrary SQLite BLOBs",()=>{
 const a={id:"id",comic_type:1,title:"title",subtitle:"",tags:"[]",
 directory:"",chapters:"{}",cover:"",downloadedChapters:"[]",created_at:1};
 assert.notEqual(digestComicRow(a),digestComicRow({...a,created_at:2}));
 assert.notEqual(digestComicRow(a),digestComicRow({...a,created_at:"1"}));
 assert.throws(()=>digestComicRow({...a,cover:Buffer.from([1,2,3])}),/LEGACY_EVIDENCE_INVALID/);
 assert.throws(()=>digestComicRow({...a,id:""}),/LEGACY_EVIDENCE_INVALID/);
});
test("duplicate work keys in source snapshot rejected as ambiguous",async t=>{
 const {path,db}=await dbFixture(t);
 const stmt=db.prepare("INSERT INTO comics VALUES(?,?,?,?,?,?,?,?,?,?)");
 for(const title of ["A","B"])stmt.run("same",title,"","[]","d","{}","",1,"[]",1);
 db.close();
 await assert.rejects(attestLocalComicsSnapshot(path),/LEGACY_EVIDENCE_INVALID/);
});
