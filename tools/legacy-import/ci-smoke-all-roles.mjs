// CI ONLY: actual Docker sandbox integration of all five legacy input roles.
// Must NOT ship as an Import Wizard or read arbitrary real-user source folders.
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { previewAndIssueSnapshotLease } from "./docker-sandbox.mjs";
import { TrustedSnapshotLeaseRegistry } from "./snapshot-lease.mjs";
import {
  attestLocalComicsSnapshot, attestHistorySnapshot,
  attestFavoriteFoldersSnapshot, attestJsonSnapshot
} from "./record-provenance.mjs";

const temp=await mkdtemp(join(tmpdir(),"venera-l0-e2e-"));
const datasetId="33bf729f-b77d-4895-810f-bf8ca80a6d36";
const ownerScopeId="ci-verified-owner";
try {
  let db=new DatabaseSync(join(temp,"local.db"));
  db.exec("CREATE TABLE comics(id TEXT NOT NULL,title TEXT NOT NULL,subtitle TEXT NOT NULL,tags TEXT NOT NULL,directory TEXT NOT NULL,chapters TEXT NOT NULL,cover TEXT NOT NULL,comic_type INT NOT NULL,downloadedChapters TEXT NOT NULL,created_at INT,PRIMARY KEY(id,comic_type))");
  db.prepare("INSERT INTO comics VALUES(?,?,?,?,?,?,?,?,?,?)")
    .run("local1","SECRET_LOCAL_TITLE","","[]","unused","{}","",1,"[]",1);
  db.close();
  db=new DatabaseSync(join(temp,"history.db"));
  db.exec("CREATE TABLE history(id TEXT PRIMARY KEY,title TEXT,subtitle TEXT,cover TEXT,time INT,type INT,ep INT,page INT,readEpisode TEXT,max_page INT,chapter_group INT)");
  db.exec("CREATE TABLE image_favorites(id TEXT,title TEXT NOT NULL,sub_title TEXT,author TEXT,tags TEXT,translated_tags TEXT,time INT,max_page INT,source_key TEXT NOT NULL,image_favorites_ep TEXT NOT NULL,other TEXT NOT NULL,PRIMARY KEY(id,source_key))");
  db.prepare("INSERT INTO history VALUES(?,?,?,?,?,?,?,?,?,?,?)")
    .run("history1","SECRET_HISTORY_TITLE","","",1,1,0,1,"first",3,null);
  db.prepare("INSERT INTO image_favorites VALUES(?,?,?,?,?,?,?,?,?,?,?)")
    .run("image1","SECRET_IMAGE_TITLE","","","[]","[]",1,4,"provider","{}","{}");
  db.close();
  db=new DatabaseSync(join(temp,"local_favorite.db"));
  db.exec('CREATE TABLE "Quoted"" Folder" (id TEXT,name TEXT,author TEXT,type INT,tags TEXT,cover_path TEXT,time TEXT,translated_tags TEXT,display_order INT)');
  db.prepare('INSERT INTO "Quoted"" Folder" VALUES(?,?,?,?,?,?,?,?,?)')
    .run("fav1","SECRET_FAVORITE_TITLE","",1,"[]","","2025","",0);
  db.close();
  await writeFile(join(temp,"appdata.json"),JSON.stringify({
    settings:{theme_mode:"dark",enableTapToTurnPages:true,webdav:[{password:"SECRET_TOKEN"}]}
  }));
  await writeFile(join(temp,"implicitData.json"),JSON.stringify({
    cookies:"SECRET_TOKEN",oauth:"SECRET_TOKEN"
  }));
  // Unsupported Unified Store must not affect selected five roles.
  db=new DatabaseSync(join(temp,"venera.db"));
  db.exec("CREATE TABLE contents(id TEXT PRIMARY KEY)");
  db.close();

  const registry=new TrustedSnapshotLeaseRegistry();
  const {preview,leaseRef}=await previewAndIssueSnapshotLease({
    selectedDirectory:temp,ownerScopeId,datasetId,
    snapshotLeaseRegistry:registry
  });
  assert.equal(preview.status,"preview_only");
  assert.equal(preview.canCommit,false);
  assert.equal(preview.totals.inspected,5);
  assert.equal(preview.files[1].imageFavorites,1);
  assert.equal(preview.files[2].folders,1);
  assert.equal(preview.files[4].eligible,0);
  const context={leaseRef,ownerScopeId,datasetId};
  const manifest=registry.getManifest(context);
  assert.deepEqual(manifest.map(x=>x.role),
    ["local.db","history.db","local_favorite.db","appdata.json","implicitData.json"]);
  assert.equal(registry.verify({...context,inputManifest:manifest}),true);
  const proofs=[
    await attestLocalComicsSnapshot(join(temp,"local.db")),
    await attestHistorySnapshot(join(temp,"history.db")),
    await attestFavoriteFoldersSnapshot(join(temp,"local_favorite.db")),
    await attestJsonSnapshot(join(temp,"appdata.json"),"appdata.json"),
    await attestJsonSnapshot(join(temp,"implicitData.json"),"implicitData.json"),
  ];
  for(const proof of proofs)for(const record of proof.records){
    const key={datasetId,...record};
    assert.equal(registry.verifyRecord({...context,inputManifest:manifest,
      key,recordDigest:record.recordDigest}),true);
    assert.equal(registry.verifyRecord({...context,inputManifest:manifest,
      key,recordDigest:"0".repeat(64)}),false);
  }
  assert.equal(proofs[4].records.length,0);
  assert.equal(registry.verifyRecord({...context,inputManifest:manifest,
    key:{datasetId,fileRole:"implicitData.json",tableKind:"implicit",
      scopeKey:"",legacyTypeKey:"",legacyId:"cookies"},
    recordDigest:"1".repeat(64)}),false);
  const exposed=JSON.stringify(preview);
  for(const secret of ["SECRET_LOCAL_TITLE","SECRET_HISTORY_TITLE",
    "SECRET_IMAGE_TITLE","SECRET_FAVORITE_TITLE","SECRET_TOKEN",temp])
    assert.ok(!exposed.includes(secret));
  assert.equal(registry.revoke(context),true);
  assert.equal(registry.verify({...context,inputManifest:manifest}),false);
  process.stdout.write("PASS: five-role Docker snapshot and private record proof verification\n");
}finally{
  await rm(temp,{recursive:true,force:true});
}
