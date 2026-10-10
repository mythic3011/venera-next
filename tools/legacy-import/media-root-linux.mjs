// LINUX-ONLY host/private media-root capability. Never call from a renderer,
// plugin, HTTP route, or with a raw legacy DB absolute "directory" value.
// Native macOS/Windows adapters need separate OS security review.
//
// Linux /proc/self/fd/N/<child> + O_NOFOLLOW/O_DIRECTORY anchors every step
// to an already-open dir FD (openat-style); no string starts from the old DB.
// Zero writable flags; no network; no symlink escape. Mount namespaces and
// kernel/host security still belong to the trusted native shell.
import { open, realpath } from "node:fs/promises";
import { constants } from "node:fs";
import { createHash } from "node:crypto";
import { isAbsolute } from "node:path";

const MAX_BYTES=64*1024*1024;
const MAX_SEGMENTS=24;
const MAX_GRANTS=4;
const MAX_LIFETIME_MS=5*60*1000;
const IMAGE_EXTENSIONS=new Set(["jpg","jpeg","png","gif","webp","avif"]);
const DIRECTORY_FLAGS=constants.O_RDONLY|constants.O_DIRECTORY|constants.O_NOFOLLOW|
  (constants.O_CLOEXEC||0)|(constants.O_NONBLOCK||0);
const FILE_FLAGS=constants.O_RDONLY|constants.O_NOFOLLOW|
  (constants.O_CLOEXEC||0)|(constants.O_NONBLOCK||0);
const HEX16=/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
export class MediaGrantError extends Error {
  constructor(code){super(code);this.name="MediaGrantError";this.code=code;}
}
function deny(code){throw new MediaGrantError(code);}
function scopeText(s){
  if(typeof s!=="string"||!s||s.length>256||s.includes("\0"))deny("MEDIA_SCOPE_INVALID");
  return s;
}
function validSegments(parts) {
  if(!Array.isArray(parts)||parts.length<1||parts.length>MAX_SEGMENTS)
    deny("MEDIA_RELATIVE_PATH_INVALID");
  for(const x of parts)if(typeof x!=="string"||x.length===0||
    x==="."||x===".."||x.includes("/")||x.includes("\\")||
    x.includes("\0")||Buffer.byteLength(x,"utf8")>255)
    deny("MEDIA_RELATIVE_PATH_INVALID");
  const leaf=parts.at(-1),extension=leaf.split(".").at(-1)?.toLowerCase();
  if(!IMAGE_EXTENSIONS.has(extension))deny("MEDIA_UNSUPPORTED_FILE");
}
function knownImage(buffer) {
  if(buffer.length>=8 && buffer.subarray(0,8).equals(
    Buffer.from([137,80,78,71,13,10,26,10])))return "image/png";
  if(buffer.length>=3 && buffer[0]===255&&buffer[1]===216&&buffer[2]===255)
    return "image/jpeg";
  if(buffer.length>=6 &&
    ["GIF87a","GIF89a"].includes(buffer.subarray(0,6).toString("ascii")))
    return "image/gif";
  if(buffer.length>=12 && buffer.subarray(0,4).toString("ascii")==="RIFF" &&
    buffer.subarray(8,12).toString("ascii")==="WEBP")return "image/webp";
  if(buffer.length>=16 && buffer.subarray(4,8).toString("ascii")==="ftyp" &&
    ["avif","avis"].includes(buffer.subarray(8,12).toString("ascii")))
    return "image/avif";
  deny("MEDIA_MAGIC_INVALID");
}
function acceptedExtension(mime,filename){
  const ext=filename.split(".").at(-1).toLowerCase();
  const allowed={
    "image/png":["png"],"image/jpeg":["jpg","jpeg"],"image/gif":["gif"],
    "image/webp":["webp"],"image/avif":["avif"]
  }[mime];
  if(!allowed?.includes(ext))deny("MEDIA_EXTENSION_MISMATCH");
}
function nowMillis(){return Date.now();}
export class TrustedLinuxMediaRootGrants {
  #grants=new Map();#clock;
  constructor({now=nowMillis}={}){
    if(process.platform!=="linux")deny("MEDIA_PLATFORM_UNSUPPORTED");
    if(typeof now!=="function")deny("MEDIA_CLOCK_INVALID");
    this.#clock=now;
  }
  async #revokeObject(grant,entry){
    if(this.#grants.get(grant)!==entry)return;
    this.#grants.delete(grant);
    clearTimeout(entry.timer);
    await entry.directory.close().catch(()=>{});
  }
  async grantFromTrustedPicker({ownerScopeId,datasetId,requestTrustedDirectory,
    ttlMs=MAX_LIFETIME_MS}) {
    scopeText(ownerScopeId);
    if(!HEX16.test(datasetId)||typeof requestTrustedDirectory!=="function"||
      !Number.isSafeInteger(ttlMs)||ttlMs<1||ttlMs>MAX_LIFETIME_MS)
      deny("MEDIA_TRUSTED_PICKER_REQUIRED");
    if(this.#grants.size>=MAX_GRANTS)deny("MEDIA_GRANT_CAPACITY");
    // This callback MUST be a trusted native directory-selection/consent
    // gesture. User old-db paths or JavaScript plugin output are not grants.
    let root;
    try{root=await requestTrustedDirectory();}
    catch{deny("MEDIA_GRANT_CANCELLED");}
    if(typeof root!=="string"||!isAbsolute(root)||root.includes("\0")||
       root.length>4096)deny("MEDIA_ROOT_INVALID");
    // A top-level filesystem root is never a narrow comic/media grant.
    // e.g. "/", "/home", "/etc", "/proc", "/mnt" or "/tmp".
    if(root.split("/").filter(Boolean).length<2)
      deny("MEDIA_ROOT_TOO_BROAD");
    let dir;
    try{
      dir=await open(root,DIRECTORY_FLAGS);
      const st=await dir.stat();
      if(!st.isDirectory())deny("MEDIA_ROOT_INVALID");
      // Reject any symlinked parent in the picker path; alternative native
      // platform adapters should bind a true OS file handle/bookmark instead.
      const canonical=await realpath(root);
      if(canonical!==root)deny("MEDIA_ROOT_SYMLINK");
    }catch(e){
      await dir?.close().catch(()=>{});
      if(e instanceof MediaGrantError)throw e;
      deny("MEDIA_ROOT_UNAVAILABLE");
    }
    const ref=Object.freeze(Object.create(null));
    const entry={ownerScopeId,datasetId,directory:dir,
      deadline:this.#clock()+ttlMs,timer:null};
    this.#grants.set(ref,entry);
    entry.timer=setTimeout(()=>{void this.#revokeObject(ref,entry);},ttlMs);
    entry.timer.unref?.();
    return ref; // opaque, not a path or serializable grant token
  }
  #entry({grant,ownerScopeId,datasetId}) {
    if(!grant||typeof grant!=="object"||!HEX16.test(datasetId)||
       typeof ownerScopeId!=="string")deny("MEDIA_SCOPE_DENIED");
    const e=this.#grants.get(grant);
    if(!e || e.ownerScopeId!==ownerScopeId || e.datasetId!==datasetId)
      deny("MEDIA_SCOPE_DENIED");
    if(this.#clock()>=e.deadline)deny("MEDIA_GRANT_EXPIRED");
    return e;
  }
  async readImage({grant,ownerScopeId,datasetId,relativeSegments}) {
    const e=this.#entry({grant,ownerScopeId,datasetId});
    validSegments(relativeSegments);
    let parent=e.directory,ownedParent=null,leaf=null;
    try{
      for(let i=0;i<relativeSegments.length-1;i++){
        const handle=await open("/proc/self/fd/"+parent.fd+"/"+relativeSegments[i],
          DIRECTORY_FLAGS);
        const st=await handle.stat();
        if(!st.isDirectory()){await handle.close();deny("MEDIA_PATH_NOT_DIRECTORY");}
        await ownedParent?.close();
        ownedParent=handle;parent=handle;
      }
      leaf=await open("/proc/self/fd/"+parent.fd+"/"+relativeSegments.at(-1),FILE_FLAGS);
      const before=await leaf.stat();
      if(!before.isFile() || before.size<8 || before.size>MAX_BYTES)
        deny("MEDIA_NOT_BOUNDED_REGULAR_FILE");
      const chunks=[],buf=Buffer.allocUnsafe(128*1024);
      let total=0;
      while(true){
        const {bytesRead}=await leaf.read(buf,0,Math.min(buf.length,MAX_BYTES+1-total),null);
        if(bytesRead===0)break;
        total+=bytesRead;
        if(total>MAX_BYTES)deny("MEDIA_FILE_TOO_LARGE");
        chunks.push(Buffer.from(buf.subarray(0,bytesRead)));
      }
      const after=await leaf.stat();
      if(before.dev!==after.dev||before.ino!==after.ino||
         before.size!==after.size||before.mtimeMs!==after.mtimeMs||
         before.ctimeMs!==after.ctimeMs||total!==before.size)
        deny("MEDIA_CHANGED_DURING_READ");
      this.#entry({grant,ownerScopeId,datasetId}); // reject expiry mid-read
      const bytes=Buffer.concat(chunks,total);
      const mimeType=knownImage(bytes);
      acceptedExtension(mimeType,relativeSegments.at(-1));
      return {bytes,mimeType,sizeBytes:total,
        sha256:createHash("sha256").update(bytes).digest("hex")};
    }catch(err){
      if(err instanceof MediaGrantError)throw err;
      deny("MEDIA_READ_DENIED");
    }finally{
      await leaf?.close().catch(()=>{});
      await ownedParent?.close().catch(()=>{});
    }
  }
  async revoke({grant,ownerScopeId,datasetId}) {
    const e=this.#entry({grant,ownerScopeId,datasetId});
    await this.#revokeObject(grant,e);
    return true;
  }
}
