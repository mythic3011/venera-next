// Host-side *declassification* of untrusted subprocess stdout.
// The sandboxed parser's JSON is DATA, not a trusted contract by itself.
const ROLES = ["local.db","history.db","local_favorite.db","appdata.json","implicitData.json"];
const STATES = new Set(["inspected","missing","rejected"]);
const VARIANTS = new Set(["distributed-v1","legacy-appdata","legacy-implicit"]);
const ERRORS = new Set([
 "SKIPPED_MISSING_INPUT","LEGACY_SOURCE_UNREADABLE","LEGACY_INPUT_NOT_ALLOWED",
 "LEGACY_DATA_BUDGET_EXCEEDED","LEGACY_SCHEMA_UNSUPPORTED","LEGACY_SOURCE_CORRUPT",
 "LEGACY_SNAPSHOT_UNAVAILABLE","LEGACY_JSON_INVALID_UTF8","LEGACY_JSON_UNSAFE_KEY",
 "LEGACY_JSON_MALFORMED","LEGACY_LIMIT_INVALID","LEGACY_UNIFIED_STORE_UNSUPPORTED"
]);
const FILE_NUMS = ["records","eligible","deferred","reviewRequired","invalid",
                   "imageFavorites","skipped","folders"];
const TOTAL_NUMS = ["inspected","missing","rejected","records","eligible","deferred",
                    "reviewRequired","invalid"];
const ROOT_KEYS = new Set(["status","scope","readOnly","canCommit","phase","totals","files"]);
const FILE_KEYS = new Set(["role","status","code","schemaVariant",...FILE_NUMS]);
function bad() { throw new Error("SANDBOX_RESULT_INVALID"); }
function obj(v) { return v !== null && typeof v==="object" && !Array.isArray(v); }
function safeCount(x) { return Number.isSafeInteger(x) && x>=0 && x<=1_000_000; }
export function sanitizeSandboxResult(data) {
  if (!obj(data) || Object.keys(data).some(k=>!ROOT_KEYS.has(k)) ||
      data.scope!=="old-venera-five-distributed-files" ||
      data.readOnly!==true || data.canCommit!==false || data.phase!=="L0" ||
      !["needs_attention","preview_only","no_inputs"].includes(data.status) ||
      !Array.isArray(data.files) || data.files.length!==5 ||
      !obj(data.totals) ||
      Object.keys(data.totals).some(k=>!TOTAL_NUMS.includes(k)) ||
      TOTAL_NUMS.some(k=>!safeCount(data.totals[k]))) bad();
  const publicFiles = data.files.map((file,i)=>{
    if (!obj(file) || Object.keys(file).some(k=>!FILE_KEYS.has(k)) ||
        file.role!==ROLES[i] || !STATES.has(file.status)) bad();
    const result={role:file.role,status:file.status};
    if (file.status==="inspected") {
      if (!VARIANTS.has(file.schemaVariant) || "code" in file) bad();
      result.schemaVariant=file.schemaVariant;
    } else {
      if (!ERRORS.has(file.code) || "schemaVariant" in file) bad();
      result.code=file.code;
    }
    for (const key of FILE_NUMS) {
      if (key in file) {
        if (file.status!=="inspected" || !safeCount(file[key])) bad();
        result[key]=file[key];
      }
    }
    return result;
  });
  const totals={};
  for(const key of TOTAL_NUMS)totals[key]=data.totals[key];
  for(const state of STATES) {
    if(totals[state]!==publicFiles.filter(f=>f.status===state).length) bad();
  }
  for(const key of ["records","eligible","deferred","reviewRequired","invalid"]) {
    if(totals[key]!==publicFiles.reduce((n,f)=>n+(f[key]||0),0)) bad();
  }
  const expectedStatus=totals.rejected||totals.invalid?"needs_attention":
    totals.inspected?"preview_only":"no_inputs";
  if(data.status!==expectedStatus)bad();
  return Object.freeze({
    status:data.status,scope:data.scope,readOnly:true,canCommit:false,
    phase:"L0", totals:Object.freeze(totals),
    files:Object.freeze(publicFiles.map(f=>Object.freeze(f)))
  });
}
