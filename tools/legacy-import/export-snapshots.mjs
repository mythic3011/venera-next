// Isolated container worker: write consistent old-Venera role snapshots into
// host-approved PRIVATE output mount, never into the new v2 database.
// Must run under Docker --network=none, read-only input/code mounts, bounded tmpfs.
import { backup, DatabaseSync } from "node:sqlite";
import { lstat, readFile, writeFile, chmod, stat } from "node:fs/promises";
import { join } from "node:path";
import { previewLegacyDirectory, INPUT_ROLES } from "./l0.mjs";

const MAX_DB=48*1024*1024,MAX_JSON=4*1024*1024;
function fail(){throw new Error("LEGACY_SNAPSHOT_EXPORT_FAILED");}
function validFile(st){return st.isFile() && !st.isSymbolicLink();}
async function exportRole(sourceDir,outDir,role){
  const from=join(sourceDir,role),to=join(outDir,role);
  let st;
  try {st=await lstat(from);}
  catch(e){if(e.code==="ENOENT")return false;fail();}
  if(!validFile(st) || st.size > (role.endsWith(".db")?MAX_DB:MAX_JSON))fail();
  if(role.endsWith(".db")){
    let db;
    try {
      db=new DatabaseSync(from,{readOnly:true});
      db.exec("PRAGMA trusted_schema=OFF; PRAGMA query_only=ON");
      await backup(db,to); // SQLite-consistent snapshot, committed WAL included
    } catch{fail();}
    finally{db?.close();}
    const result=await lstat(to);
    if(!validFile(result) || result.size>2*MAX_DB)fail();
    await chmod(to,0o600);
  }else{
    const contents=await readFile(from);
    if(contents.length>MAX_JSON)fail();
    await writeFile(to,contents,{flag:"wx",mode:0o600});
    contents.fill(0); // best effort; not a substitute for disk encryption
  }
  return true;
}
const argv=process.argv.slice(2);
if(argv.length!==4 || argv[0]!=="--dir" || argv[2]!=="--out" ||
   argv[1]!=="/legacy" || argv[3]!=="/out")fail();
const output=await stat("/out");
if(!output.isDirectory())fail();
try {
  for(const role of INPUT_ROLES)await exportRole("/legacy","/out",role);
  // Crucially, inspect exactly the SAME exported snapshots which the trusted
  // host later pins in the lease; do not inspect one version and reopen originals.
  const result=await previewLegacyDirectory("/out");
  if(result.status==="needs_attention")fail(); // fail closed; host deletes staging
  process.stdout.write(JSON.stringify(result)+"\n");
} catch {
  process.stderr.write("LEGACY_SNAPSHOT_EXPORT_FAILED\n"); // no paths/data
  process.exitCode=1;
}
