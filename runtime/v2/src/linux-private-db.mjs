// Host-only Linux private AppData database owner; NOT a renderer/plugin API.
// Exposes no configurable database filename. Never migrate old Venera files.
// Native Windows/macOS host lifecycle requires separately reviewed adapters.
import { DatabaseSync } from "node:sqlite";
import { constants } from "node:fs";
import { lstat,open,realpath,unlink } from "node:fs/promises";
import { resolve,join } from "node:path";
import { initializeFreshV2Database,loadReviewedFreshV2Sql } from
  "./schema-bootstrap.mjs";
import { bindTrustedFreshV2Sqlite } from "./host-sqlite.mjs";

export class V2HostFileError extends Error {
 constructor(code){super(code);this.name="V2HostFileError";this.code=code;}
}
const deny=code=>{throw new V2HostFileError(code);};
const DB_NAME="venera.db"; // New v2 OUTPUT only. Old venera.db is never input.
async function trustedDir(value){
 if(process.platform!=="linux" || !Number.isSafeInteger(process.getuid?.()))
   deny("V2_FILE_PLATFORM_UNSUPPORTED");
 if(typeof value!=="string"||!value.startsWith("/")||value.includes("\0")||
    value.length>4096)deny("V2_APPDATA_DIR_INVALID");
 const path=resolve(value);
 let info,canonical;
 try{
   info=await lstat(path);
   canonical=await realpath(path);
 }catch{deny("V2_APPDATA_DIR_INVALID");}
 if(!info.isDirectory()||info.isSymbolicLink()||canonical!==path ||
    info.uid!==process.getuid() || (info.mode&0o077)!==0)
   deny("V2_APPDATA_DIR_UNTRUSTED");
 return path;
}
function openBound(path) {
 let db;
 try{
   db=new DatabaseSync(path,{create:false});
   db.exec("PRAGMA foreign_keys=ON; PRAGMA busy_timeout=2000");
   if(db.prepare("PRAGMA foreign_keys").get().foreign_keys!==1)
     deny("V2_FOREIGN_KEYS_OFF");
   const runtime=bindTrustedFreshV2Sqlite(db);
   return Object.freeze({runtime,close:()=>db.close(),
     schemaFamily:"fresh-v2-content-unit",storageScope:"host_private"});
 }catch(e){
   db?.close();
   if(e instanceof V2HostFileError)throw e;
   deny("V2_FILE_OPEN_INVALID_SCHEMA");
 }
}
export async function createTrustedPrivateV2Database({appDataDirectory}={}){
 const dir=await trustedDir(appDataDirectory),path=join(dir,DB_NAME);
 let fd,db;
 try{
   fd=await open(path,constants.O_RDWR|constants.O_CREAT|constants.O_EXCL|
     constants.O_NOFOLLOW,0o600);
   await fd.close();fd=null;
 }catch{
   await fd?.close().catch(()=>{});
   deny("V2_FILE_ALREADY_EXISTS_OR_DENIED");
 }
 try{
   db=new DatabaseSync(path,{create:false});
   db.exec("PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL");
   initializeFreshV2Database(db,await loadReviewedFreshV2Sql());
   db.exec("PRAGMA journal_mode=WAL");
   db.close();db=null;
   return openBound(path);
 }catch(e){
   db?.close();
   await unlink(path).catch(()=>{});
   if(e instanceof V2HostFileError)throw e;
   deny("V2_FILE_CREATE_FAILED");
 }
}
export async function reopenTrustedPrivateV2Database({appDataDirectory}={}){
 const dir=await trustedDir(appDataDirectory),path=join(dir,DB_NAME);
 let info;
 try{info=await lstat(path);}
 catch{deny("V2_FILE_NOT_FOUND");}
 if(!info.isFile()||info.isSymbolicLink()||
   info.uid!==process.getuid()||(info.mode&0o077)!==0)
   deny("V2_FILE_UNTRUSTED");
 return openBound(path);
}
