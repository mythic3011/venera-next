import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { mkdtemp,chmod,lstat,readFile,rm,symlink } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createTrustedPrivateV2Database,reopenTrustedPrivateV2Database,
  V2HostFileError } from "../src/linux-private-db.mjs";

const denied=code=>e=>e instanceof V2HostFileError&&e.code===code;
async function appdata(t){
 const dir=await mkdtemp(join(tmpdir(),"venera-v2-private-"));
 t.after(()=>rm(dir,{recursive:true,force:true}));
 return dir;
}
test("private file-backed NEW v2 DB persists ContentUnit session across host reopen",async t=>{
 const dir=await appdata(t);
 const first=await createTrustedPrivateV2Database({appDataDirectory:dir});
 assert.equal(first.schemaFamily,"fresh-v2-content-unit");
 const content=first.runtime.createContentDraft({title:"Local draft"});
 const section=first.runtime.addSectionDraft({
   contentId:content.contentId,unitIndexes:[0,2]
 });
 first.runtime.updateReaderPosition({
   contentId:content.contentId,unitId:section.units[1].id
 });
 first.close();
 const file=await lstat(join(dir,"venera.db"));
 assert.equal(file.isFile(),true);
 assert.equal(file.mode&0o077,0);
 const second=await reopenTrustedPrivateV2Database({appDataDirectory:dir});
 try{
   assert.equal(second.runtime.getReaderPosition({
     contentId:content.contentId
   }).unitIndex,2);
   assert.equal(second.runtime.openSection({
     contentId:content.contentId,sectionId:section.sectionId
   }).units.length,2);
 }finally{second.close();}
});
test("cannot overwrite an existing v2 DB or silently reinterpret old venera.db",async t=>{
 const dir=await appdata(t);
 const first=await createTrustedPrivateV2Database({appDataDirectory:dir});
 first.close();
 await assert.rejects(createTrustedPrivateV2Database({appDataDirectory:dir}),
   denied("V2_FILE_ALREADY_EXISTS_OR_DENIED"));
 const reopened=await reopenTrustedPrivateV2Database({appDataDirectory:dir});
 reopened.close();
 const other=await appdata(t);
 const old=new DatabaseSync(join(other,"venera.db"));
 old.exec("CREATE TABLE comics(id TEXT PRIMARY KEY)");
 old.close();
 await chmod(join(other,"venera.db"),0o600); // first pass file ACL gate; then reject old schema
 await assert.rejects(reopenTrustedPrivateV2Database({
   appDataDirectory:other
 }),denied("V2_FILE_OPEN_INVALID_SCHEMA"));
 await assert.rejects(createTrustedPrivateV2Database({
   appDataDirectory:other
 }),denied("V2_FILE_ALREADY_EXISTS_OR_DENIED"));
 const header=await readFile(join(other,"venera.db"));
 assert.equal(header.subarray(0,16).toString("binary"),"SQLite format 3\0");
});
test("requires private owned AppData directory; broad or symlinked directory denied",async t=>{
 const dir=await appdata(t);
 await chmod(dir,0o755);
 await assert.rejects(createTrustedPrivateV2Database({appDataDirectory:dir}),
   denied("V2_APPDATA_DIR_UNTRUSTED"));
 await chmod(dir,0o700);
 const parent=await appdata(t);
 const symlinkDir=join(parent,"link");
 await symlink(dir,symlinkDir);
 await assert.rejects(createTrustedPrivateV2Database({
   appDataDirectory:symlinkDir
 }),denied("V2_APPDATA_DIR_UNTRUSTED"));
 for(const bad of ["venera.db","../bad","/does-not-exist/no-data",null])
   await assert.rejects(createTrustedPrivateV2Database({
     appDataDirectory:bad
   }),denied("V2_APPDATA_DIR_INVALID"));
});
test("reopen rejects symlinked database or world-readable DB permission",async t=>{
 const dir=await appdata(t);
 const opened=await createTrustedPrivateV2Database({appDataDirectory:dir});
 opened.close();
 await chmod(join(dir,"venera.db"),0o644);
 await assert.rejects(reopenTrustedPrivateV2Database({appDataDirectory:dir}),
   denied("V2_FILE_UNTRUSTED"));
 const other=await appdata(t);
 await symlink(join(dir,"venera.db"),join(other,"venera.db"));
 await assert.rejects(reopenTrustedPrivateV2Database({appDataDirectory:other}),
   denied("V2_FILE_UNTRUSTED"));
});
