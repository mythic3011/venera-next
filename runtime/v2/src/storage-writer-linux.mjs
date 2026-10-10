// Linux trusted-host v2 storage-object writer (independent of legacy LGI).
// No old venera.db, legacy plan_only, renderer, plugin or arbitrary SQL API.
// This deliberately creates a *detached* StorageObject, NOT a ContentUnit.
import { createHash,randomUUID } from "node:crypto";
import { constants } from "node:fs";
import { lstat,realpath,open,mkdir,readFile,link,unlink } from "node:fs/promises";
import { join,resolve } from "node:path";
import { TrustedLinuxMediaRootGrants } from
  "../../../tools/legacy-import/media-root-linux.mjs";

export class V2StorageWriteError extends Error {
 constructor(code){super(code);this.name="V2StorageWriteError";this.code=code;}
}
const fail=c=>{throw new V2StorageWriteError(c);};
const SHA=v=>createHash("sha256").update(v).digest("hex");
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const MAX_BYTES=64*1024*1024;
const DIR_FLAGS=constants.O_RDONLY|constants.O_DIRECTORY|constants.O_NOFOLLOW|
 (constants.O_CLOEXEC||0);
const INTERNAL_KEY="v2_managed_local";
const owner=()=>process.getuid?.();
const fdpath=(fd,name)=>"/proc/self/fd/"+fd+"/"+name;
function bytesMatch(actual,sha,size){
 return actual.length===size && SHA(actual)===sha;
}
async function privateDir(path){
 if(process.platform!=="linux" || !Number.isSafeInteger(owner()))
   fail("V2_STORAGE_PLATFORM_UNSUPPORTED");
 if(typeof path!=="string" || !path.startsWith("/") || path.includes("\0") ||
    path.length>4096)fail("V2_STORAGE_ROOT_INVALID");
 const p=resolve(path);
 let st,real;
 try {st=await lstat(p);real=await realpath(p);}
 catch {fail("V2_STORAGE_ROOT_INVALID");}
 if(!st.isDirectory()||st.isSymbolicLink()||st.uid!==owner()||
    (st.mode&0o077)!==0 || real!==p)
   fail("V2_STORAGE_ROOT_UNTRUSTED");
 return p;
}
async function directory(parent,name) {
 const path=fdpath(parent.fd,name);
 try {await mkdir(path,{mode:0o700});}
 catch(e){if(e.code!=="EEXIST")fail("V2_STORAGE_DIRECTORY_DENIED");}
 let handle;
 try {
   handle=await open(path,DIR_FLAGS);
   const st=await handle.stat(),base=await parent.stat();
   if(!st.isDirectory() || st.uid!==owner() || (st.mode&0o077)!==0 ||
      st.dev!==base.dev)fail("V2_STORAGE_DIRECTORY_UNTRUSTED");
   return handle;
 }catch(e){
   await handle?.close().catch(()=>{});
   if(e instanceof V2StorageWriteError)throw e;
   fail("V2_STORAGE_DIRECTORY_UNTRUSTED");
 }
}
function verifyRootDb(db) {
 if(!db || typeof db.prepare!=="function" || typeof db.exec!=="function")
   fail("V2_STORAGE_DB_REQUIRED");
 const tables=new Set(db.prepare(
   "SELECT name FROM sqlite_master WHERE type='table'"
 ).all().map(x=>x.name));
 if(["storage_backends","storage_objects","storage_placements",
      "v2_storage_write_journal"].some(x=>!tables.has(x)) ||
    ["comics","chapters","pages","reader_sessions"].some(x=>tables.has(x)))
   fail("V2_STORAGE_CANONICAL_SCHEMA_REQUIRED");
 if(db.prepare("PRAGMA foreign_keys").get().foreign_keys!==1)
   fail("V2_STORAGE_FOREIGN_KEYS_OFF");
}
function transaction(db,fn){
 db.exec("BEGIN IMMEDIATE");
 try{const value=fn();db.exec("COMMIT");return value;}
 catch(e){db.exec("ROLLBACK");throw e;}
}
function backend(db) {
 let value=db.prepare("SELECT id,backend_kind,status FROM storage_backends WHERE backend_key=?")
   .get(INTERNAL_KEY);
 if(value){
   if(value.backend_kind!=="local_app_data"||value.status!=="active")
     fail("V2_STORAGE_BACKEND_CONFLICT");
   return value.id;
 }
 const id=randomUUID(),at=new Date().toISOString();
 db.prepare(
   "INSERT INTO storage_backends(id,backend_key,display_name,backend_kind,config_json,"+
   "config_schema_version,status,created_at,updated_at) VALUES(?,?,?,'local_app_data','{}',1,'active',?,?)"
 ).run(id,INTERNAL_KEY,"Venera v2 managed private objects",at,at);
 return id;
}
async function synced(handle) {
 await handle.sync();
}
export async function createTrustedV2StorageWriter({
 canonicalDb,appDataDirectory,trustedMediaRootResolver,gestureAuthority,
 // test-only failpoint. Production host never exposes this argument via IPC.
 checkpoint=async()=>{}
}={}){
 verifyRootDb(canonicalDb);
 canonicalDb.exec("PRAGMA synchronous=FULL"); // crash-aware on this host connection
 if(!(trustedMediaRootResolver instanceof TrustedLinuxMediaRootGrants) ||
    !gestureAuthority || typeof gestureAuthority.confirm!=="function" ||
    typeof gestureAuthority.verifyTrustedUserGesture!=="function" ||
    typeof checkpoint!=="function")fail("V2_STORAGE_HOST_AUTHORITY_REQUIRED");
 const root=await open(await privateDir(appDataDirectory),DIR_FLAGS);
 let stage,objects;
 try{
   stage=await directory(root,".v2-stage");
   objects=await directory(root,"v2-objects");
 }catch(e){
   await objects?.close().catch(()=>{});
   await stage?.close().catch(()=>{});
   await root.close();
   throw e;
 }
 const plans=new WeakMap();
 let closed=false;
 const alive=()=>{if(closed)fail("V2_STORAGE_WRITER_CLOSED");};
 const validName=(key,extension)=>typeof key==="string" &&
   new RegExp("^[0-9a-f-]{36}\\."+extension+"$").test(key) &&
   UUID.test(key.slice(0,-(extension.length+1)));
 async function inspectPhysical(dir,key,expectedSha,expectedBytes){
   let file;
   try {
     file=await open(fdpath(dir.fd,key),
       constants.O_RDONLY|constants.O_NOFOLLOW|(constants.O_NONBLOCK||0));
   }catch(e){
     return {exists:e?.code!=="ENOENT",matches:false};
   }
   try{
     const initial=await file.stat();
     if(!initial.isFile()||initial.size!==expectedBytes ||
        initial.size<1||initial.size>MAX_BYTES)
       return {exists:true,matches:false};
     const hasher=createHash("sha256"),chunk=Buffer.allocUnsafe(65536);
     let total=0;
     while(total<expectedBytes){
       const {bytesRead}=await file.read(chunk,0,
         Math.min(chunk.length,expectedBytes-total),total);
       if(bytesRead<=0)return {exists:true,matches:false};
       hasher.update(chunk.subarray(0,bytesRead));
       total+=bytesRead;
     }
     const trailing=await file.read(chunk,0,1,total);
     const final=await file.stat();
     return {exists:true,matches:trailing.bytesRead===0 &&
       final.dev===initial.dev && final.ino===initial.ino &&
       final.size===initial.size && final.mtimeMs===initial.mtimeMs &&
       final.ctimeMs===initial.ctimeMs && hasher.digest("hex")===expectedSha};
   }catch{return {exists:true,matches:false};}
   finally{await file.close().catch(()=>{});}
 }
 async function auditRow(row){
   if(!validName(row.object_key,"blob")||!validName(row.stage_key,"part"))
     return {journalId:row.id,status:"invalid_journal_record_review"};
   const final=await inspectPhysical(objects,row.object_key,
     row.expected_sha256,row.expected_bytes);
   const staged=await inspectPhysical(stage,row.stage_key,
     row.expected_sha256,row.expected_bytes);
   if(row.state==="committed"){
     const object=canonicalDb.prepare(
       "SELECT content_hash,size_bytes,mime_type FROM storage_objects WHERE id=?"
     ).get(row.planned_storage_id);
     const place=canonicalDb.prepare(
       "SELECT role,sync_status,object_key FROM storage_placements WHERE id=? "+
       "AND storage_object_id=? AND storage_backend_id=?"
     ).get(row.planned_placement_id,row.planned_storage_id,row.storage_backend_id);
     return {journalId:row.id,status:final.matches && object?.content_hash===row.expected_sha256 &&
       object?.size_bytes===row.expected_bytes &&
       object?.mime_type===row.expected_mime_type &&
       place?.role==="authority"&&place?.sync_status==="synced"&&
       place?.object_key===row.object_key?"healthy":"storage_unavailable"};
   }
   if(final.matches)return {journalId:row.id,status:"promoted_uncommitted_review"};
   if(final.exists)return {journalId:row.id,status:"promoted_corrupt_review"};
   if(staged.matches)return {journalId:row.id,status:"staged_uncommitted_review"};
   if(staged.exists)return {journalId:row.id,status:"staged_corrupt_review"};
   return {journalId:row.id,status:"missing_uncommitted_review"};
 }
 const api={
   async inspectGrantedImage({ownerScopeId,datasetId,mediaGrant,relativeSegments,
     objectKind="unit_image"}={}){
     alive();
     if(typeof ownerScopeId!=="string"||!ownerScopeId||!UUID.test(datasetId)||
        !["unit_image","cover"].includes(objectKind))
       fail("V2_STORAGE_SCOPE_INVALID");
     const result=await trustedMediaRootResolver.readImage({
       grant:mediaGrant,ownerScopeId,datasetId,relativeSegments
     });
     try{
       if(result.sizeBytes<8||result.sizeBytes>MAX_BYTES ||
          !bytesMatch(result.bytes,result.sha256,result.sizeBytes))
         fail("V2_STORAGE_INPUT_CHANGED");
       const objectId=randomUUID(),placementId=randomUUID(),journalId=randomUUID();
       const stageKey=journalId+".part",objectKey=objectId+".blob";
       const body=["v2-storage-write-v1","storage_object_only",ownerScopeId,datasetId,
          journalId,objectId,placementId,objectKind,result.sha256,
          result.sizeBytes,result.mimeType];
       const planDigest=SHA(Buffer.from(JSON.stringify(body)));
       const plan=Object.freeze(Object.create(null));
       const state={ownerScopeId,datasetId,mediaGrant,
         relativeSegments:Object.freeze([...relativeSegments]),
         objectKind,objectId,placementId,journalId,stageKey,objectKey,
         expectedSha:result.sha256,expectedBytes:result.sizeBytes,
         mimeType:result.mimeType,planDigest,used:false};
       const preview=Object.freeze({scope:"storage_object_only",objectKind,
         expectedBytes:result.sizeBytes,sha256Prefix:result.sha256.slice(0,12),
         canAttachContent:false,canImportLegacy:false});
       state.preview=preview;
       plans.set(plan,state);
       return Object.freeze({plan,preview});
     }finally{result.bytes.fill(0);}
   },
   async approveAndWrite({plan,preview}={}){
     alive();
     const state=plans.get(plan);
     if(!state||state.used || state.preview!==preview)
       fail("V2_STORAGE_PLAN_INVALID");
     state.used=true;
     const context={ownerScopeId:state.ownerScopeId,datasetId:state.datasetId,
       planDigest:state.planDigest};
     const gesture=await gestureAuthority.confirm(context,preview);
     if(await gestureAuthority.verifyTrustedUserGesture(gesture,context)!==true)
       fail("V2_STORAGE_GESTURE_REJECTED");
     // A second OS-granted read after human confirmation catches a changed or
     // revoked source root. The copied bytes are private and erased in finally.
     const result=await trustedMediaRootResolver.readImage({
       grant:state.mediaGrant,ownerScopeId:state.ownerScopeId,
       datasetId:state.datasetId,relativeSegments:state.relativeSegments
     });
     const bytes=result.bytes;
     try{
       if(!bytesMatch(bytes,state.expectedSha,state.expectedBytes) ||
          result.mimeType!==state.mimeType)
         fail("V2_STORAGE_INPUT_CHANGED");
       const db=canonicalDb,at=new Date().toISOString();
       transaction(db,()=>{
         const backendId=backend(db);
         state.backendId=backendId;
         db.prepare(
           "INSERT INTO v2_storage_write_journal "+
           "(id,owner_scope_id,dataset_id,planned_storage_id,planned_placement_id,"+
           "storage_backend_id,object_kind,expected_sha256,expected_bytes,"+
           "expected_mime_type,stage_key,object_key,state,authorization_scope,"+
           "authorization_digest,created_at,updated_at) "+
           "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,'intent','storage_object_only',?,?,?)"
         ).run(state.journalId,state.ownerScopeId,state.datasetId,state.objectId,
           state.placementId,backendId,state.objectKind,state.expectedSha,
           state.expectedBytes,state.mimeType,state.stageKey,state.objectKey,
           state.planDigest,at,at);
       });
       await checkpoint("after_intent");
       let file;
       try{
         file=await open(fdpath(stage.fd,state.stageKey),
           constants.O_CREAT|constants.O_EXCL|constants.O_WRONLY|
           constants.O_NOFOLLOW,0o600);
         await file.writeFile(bytes);
         await file.sync();
       }finally{await file?.close().catch(()=>{});}
       let verify=await readFile(fdpath(stage.fd,state.stageKey));
       const stageOk=bytesMatch(verify,state.expectedSha,state.expectedBytes);
       verify.fill(0);
       if(!stageOk)fail("V2_STORAGE_STAGE_INVALID");
       await synced(stage);
       db.prepare("UPDATE v2_storage_write_journal SET state='staged',updated_at=? WHERE id=?")
         .run(new Date().toISOString(),state.journalId);
       await checkpoint("after_stage");
       // Hard-link creation is same-volume and exclusive (EEXIST fails);
       // unlike rename() it cannot overwrite an existing managed object.
       await link(fdpath(stage.fd,state.stageKey),fdpath(objects.fd,state.objectKey));
       await synced(objects);
       await unlink(fdpath(stage.fd,state.stageKey));
       await synced(stage);
       await checkpoint("after_promotion");
       db.prepare("UPDATE v2_storage_write_journal SET state='promoted',updated_at=? WHERE id=?")
         .run(new Date().toISOString(),state.journalId);
       verify=await readFile(fdpath(objects.fd,state.objectKey));
       const finalOk=bytesMatch(verify,state.expectedSha,state.expectedBytes);
       verify.fill(0);
       if(!finalOk)fail("V2_STORAGE_PROMOTION_INVALID");
       await checkpoint("before_visibility_commit");
       transaction(db,()=>{
         const stamp=new Date().toISOString();
         db.prepare("INSERT INTO storage_objects "+
           "(id,object_kind,content_hash,size_bytes,mime_type,created_at,updated_at) "+
           "VALUES(?,?,?,?,?,?,?)"
         ).run(state.objectId,state.objectKind,state.expectedSha,state.expectedBytes,
            state.mimeType,stamp,stamp);
         db.prepare("INSERT INTO storage_placements "+
           "(id,storage_object_id,storage_backend_id,object_key,role,sync_status,"+
           "last_verified_at,created_at,updated_at) "+
           "VALUES(?,?,?,?,'authority','synced',?,?,?)"
         ).run(state.placementId,state.objectId,state.backendId,
           state.objectKey,stamp,stamp,stamp);
         db.prepare("UPDATE v2_storage_write_journal "+
           "SET state='committed',committed_at=?,updated_at=? WHERE id=?"
         ).run(stamp,stamp,state.journalId);
       });
       await checkpoint("after_visibility_commit");
       return Object.freeze({status:"storage_object_committed",
         journalId:state.journalId,storageObjectId:state.objectId,
         storagePlacementId:state.placementId,canAttachContent:false});
     }finally{bytes?.fill(0);}
   },
   // Explicit crash recovery for promoted-but-uncommitted managed bytes.
   // Requires NEW trusted human confirmation bound to original owner/dataset,
   // journal ID and immutable bytes. Never resumes legacy plan_only grants.
   async resumePromotedWithApproval({journalId,ownerScopeId,datasetId}={}){
     alive();
     if(!UUID.test(journalId)||typeof ownerScopeId!=="string"||
        !ownerScopeId||!UUID.test(datasetId))
       fail("V2_STORAGE_SCOPE_INVALID");
     const find=()=>canonicalDb.prepare(
       "SELECT * FROM v2_storage_write_journal WHERE id=? "+
       "AND owner_scope_id=? AND dataset_id=?"
     ).get(journalId,ownerScopeId,datasetId);
     const current=find();
     if(!current || current.state==="committed" ||
        current.authorization_scope!=="storage_object_only")
       fail("V2_STORAGE_RECOVERY_UNAUTHORIZED");
     if((await auditRow(current)).status!=="promoted_uncommitted_review")
       fail("V2_STORAGE_RECOVERY_BYTES_UNAVAILABLE");
     const planDigest=SHA(Buffer.from(JSON.stringify([
       "v2-storage-recovery-v1","storage_object_only",ownerScopeId,datasetId,
       journalId,current.planned_storage_id,current.planned_placement_id,
       current.expected_sha256,current.expected_bytes,current.expected_mime_type
     ])));
     const context={ownerScopeId,datasetId,planDigest};
     const preview=Object.freeze({scope:"storage_object_only",
       action:"recover_promoted_storage_only",expectedBytes:current.expected_bytes,
       sha256Prefix:current.expected_sha256.slice(0,12),
       canAttachContent:false,canImportLegacy:false});
     const gesture=await gestureAuthority.confirm(context,preview);
     if(await gestureAuthority.verifyTrustedUserGesture(gesture,context)!==true)
       fail("V2_STORAGE_RECOVERY_GESTURE_REJECTED");
     if((await auditRow(current)).status!=="promoted_uncommitted_review")
       fail("V2_STORAGE_RECOVERY_BYTES_UNAVAILABLE");
     transaction(canonicalDb,()=>{
       const locked=find();
       if(!locked || locked.state!==current.state ||
          locked.expected_sha256!==current.expected_sha256 ||
          locked.object_key!==current.object_key ||
          locked.authorization_digest!==current.authorization_digest)
         fail("V2_STORAGE_RECOVERY_CHANGED");
       // The original journal's backend must still be the active trusted
       // native local backend, never a plugin or substituted remote target.
       const target=canonicalDb.prepare(
         "SELECT backend_kind,status,backend_key FROM storage_backends WHERE id=?"
       ).get(locked.storage_backend_id);
       if(target?.backend_kind!=="local_app_data" ||
          target?.backend_key!==INTERNAL_KEY || target?.status!=="active")
         fail("V2_STORAGE_RECOVERY_BACKEND_CHANGED");
       const stamp=new Date().toISOString();
       canonicalDb.prepare("INSERT INTO storage_objects "+
         "(id,object_kind,content_hash,size_bytes,mime_type,created_at,updated_at) "+
         "VALUES(?,?,?,?,?,?,?)"
       ).run(locked.planned_storage_id,locked.object_kind,locked.expected_sha256,
         locked.expected_bytes,locked.expected_mime_type,stamp,stamp);
       canonicalDb.prepare("INSERT INTO storage_placements "+
         "(id,storage_object_id,storage_backend_id,object_key,role,sync_status,"+
         "last_verified_at,created_at,updated_at) "+
         "VALUES(?,?,?,?,'authority','synced',?,?,?)"
       ).run(locked.planned_placement_id,locked.planned_storage_id,
         locked.storage_backend_id,locked.object_key,stamp,stamp,stamp);
       canonicalDb.prepare("UPDATE v2_storage_write_journal "+
         "SET state='committed',committed_at=?,updated_at=? WHERE id=?"
       ).run(stamp,stamp,journalId);
     });
     return Object.freeze({status:"storage_object_recovered",
       journalId,storageObjectId:current.planned_storage_id,canAttachContent:false});
   },
   async auditRecovery({ownerScopeId,datasetId}={}){
     alive();
     if(typeof ownerScopeId!=="string"||!ownerScopeId||!UUID.test(datasetId))
       fail("V2_STORAGE_SCOPE_INVALID");
     const rows=canonicalDb.prepare(
       "SELECT * FROM v2_storage_write_journal WHERE owner_scope_id=? "+
       "AND dataset_id=? ORDER BY created_at,id"
     ).all(ownerScopeId,datasetId);
     const outcome=[];
     for(const row of rows)outcome.push(Object.freeze(await auditRow(row)));
     return Object.freeze(outcome);
   },
   async close(){
     if(closed)return;
     closed=true;
     await objects.close();await stage.close();await root.close();
   }
 };
 return Object.freeze(api);
}
