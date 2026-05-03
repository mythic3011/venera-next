#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="venera"
APP_BUNDLE_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
DIST_DIR="dist"
DMG_STAGE_DIR="${DIST_DIR}/dmg_contents"
DMG_OUTPUT_PATH="${DIST_DIR}/${APP_NAME}.dmg"
DMG_SHA256_PATH="${DMG_OUTPUT_PATH}.sha256"
XCODE_DESTINATION="${XCODE_DESTINATION:-platform=macOS,arch=arm64}"
START_TS="$(date +%s)"
VERBOSE="${VERBOSE:-0}"
OPEN_AFTER_BUILD="${OPEN_AFTER_BUILD:-0}"
SKIP_BUILD="${SKIP_BUILD:-0}"
CREATE_DMG="${CREATE_DMG:-0}"
KEEP_STAGE_DIR="${KEEP_STAGE_DIR:-0}"
KEEP_LOGS="${KEEP_LOGS:-0}"
WRITE_CHECKSUM="${WRITE_CHECKSUM:-1}"
DEV_RUNTIME_ROOT_OVERRIDE="${DEV_RUNTIME_ROOT_OVERRIDE:-}"
DMG_LOG_FILE=""
BUILD_LOG_FILE=""

usage() {
  cat <<'EOF'
Usage: ./scripts/build-macos-dmg.sh [options]

Options:
  --dmg           Package the built app as a DMG
  --verbose       Show raw xcodebuild and hdiutil output
  --skip-build    Reuse existing .app bundle; pair with --dmg to rebuild only the DMG
  --open          Open the built artifact after success
  --keep-stage    Keep dist/dmg_contents after success
  --keep-logs     Keep captured temp logs after success/failure
  --no-checksum   Do not write a SHA-256 checksum file next to the DMG
  --dev-runtime-root [PATH]
                  Build app with a dev-only runtime root override.
                  If PATH is omitted, use:
                  ~/Library/Application Support/com.mythic3011.veneranext.dev
  -h, --help      Show this help text

Environment:
  XCODE_DESTINATION   Override xcodebuild destination
EOF
}

step() {
  printf "\n[%s] %s\n" "$1" "$2"
}

info() {
  printf "  -> %s\n" "$1"
}

_SPINNER_PID=""

start_spinner() {
  local label="$1"
  (
    local marks='|/-\'
    local i=0
    local start_ts
    start_ts="$(date +%s)"
    while true; do
      local now elapsed mark
      now="$(date +%s)"
      elapsed="$((now - start_ts))"
      mark="${marks:i%4:1}"
      printf "\r  -> %s %s (%ss)" "$label" "$mark" "$elapsed"
      sleep 0.2
      i="$((i + 1))"
    done
  ) &
  _SPINNER_PID="$!"
}

stop_spinner() {
  if [[ -n "$_SPINNER_PID" ]]; then
    kill "$_SPINNER_PID" >/dev/null 2>&1 || true
    wait "$_SPINNER_PID" 2>/dev/null || true
    _SPINNER_PID=""
    printf "\r\033[K"
  fi
}

die() {
  printf "\n[ERROR] %s\n" "$1" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

on_error() {
  local exit_code=$?
  if [[ "$exit_code" -eq 130 ]]; then
    return
  fi
  printf "\n[FAILED] macOS build stopped (exit=%s).\n" "$exit_code" >&2
  stop_spinner
  if [[ "$KEEP_LOGS" == "1" ]]; then
    if [[ -n "$BUILD_LOG_FILE" && -f "$BUILD_LOG_FILE" ]]; then
      printf "         Build log: %s\n" "$BUILD_LOG_FILE" >&2
    fi
    if [[ -n "$DMG_LOG_FILE" && -f "$DMG_LOG_FILE" ]]; then
      printf "         DMG log:   %s\n" "$DMG_LOG_FILE" >&2
    fi
  else
    printf "         Re-run with --keep-logs to keep captured temp logs.\n" >&2
  fi
}
trap on_error ERR

cleanup_temp_files() {
  stop_spinner
  if [[ "$KEEP_LOGS" != "1" ]]; then
    [[ -n "$DMG_LOG_FILE" ]] && rm -f "$DMG_LOG_FILE" || true
    [[ -n "$BUILD_LOG_FILE" ]] && rm -f "$BUILD_LOG_FILE" || true
  fi
  if [[ "$KEEP_STAGE_DIR" != "1" ]]; then
    rm -rf "$DMG_STAGE_DIR" || true
  fi
}
trap cleanup_temp_files EXIT

on_interrupt() {
  trap - INT
  cleanup_temp_files
  printf "\n[INTERRUPTED] Build cancelled by user (Ctrl+C).\n" >&2
  printf "             Cleaning staging links to avoid partial leftovers...\n" >&2
  rm -f "${DMG_STAGE_DIR}/Applications" || true
  printf "             You can safely rerun: ./scripts/build-macos-dmg.sh\n" >&2
  exit 130
}
trap on_interrupt INT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose)
      VERBOSE=1
      ;;
    --dmg)
      CREATE_DMG=1
      ;;
    --skip-build)
      SKIP_BUILD=1
      ;;
    --open)
      OPEN_AFTER_BUILD=1
      ;;
    --keep-stage)
      KEEP_STAGE_DIR=1
      ;;
    --keep-logs)
      KEEP_LOGS=1
      ;;
    --no-checksum)
      WRITE_CHECKSUM=0
      ;;
    --dev-runtime-root)
      if [[ $# -gt 1 && "$2" != --* ]]; then
        DEV_RUNTIME_ROOT_OVERRIDE="$2"
        shift
      else
        DEV_RUNTIME_ROOT_OVERRIDE="$HOME/Library/Application Support/com.mythic3011.veneranext.dev"
      fi
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
  shift
done

step "PRECHECK" "Validating required tools and paths"
require_cmd xattr
require_cmd xcodebuild
require_cmd shasum
require_cmd ditto
if [[ "$CREATE_DMG" == "1" ]]; then
  require_cmd hdiutil
fi
mkdir -p "$DIST_DIR"
[[ -d "macos" ]] || die "Missing macos/ directory"
[[ -f "macos/Runner.xcworkspace/contents.xcworkspacedata" ]] || die "Missing Runner.xcworkspace"
info "Workspace: $ROOT_DIR"
info "Build DMG: $CREATE_DMG"
if [[ "$CREATE_DMG" == "1" ]]; then
  info "Output DMG: $DMG_OUTPUT_PATH"
else
  info "Output app: $APP_BUNDLE_PATH"
fi
info "Xcode destination: $XCODE_DESTINATION"
info "Skip build: $SKIP_BUILD"
info "Verbose: $VERBOSE"
info "Keep stage dir: $KEEP_STAGE_DIR"
info "Keep logs: $KEEP_LOGS"
info "Write checksum: $WRITE_CHECKSUM"
if [[ -n "$DEV_RUNTIME_ROOT_OVERRIDE" ]]; then
  info "Dev runtime root override: $DEV_RUNTIME_ROOT_OVERRIDE"
fi

BUILD_DB_DIR="build/macos/Build/Intermediates.noindex/XCBuildData"
if [[ "$SKIP_BUILD" != "1" ]] && [[ -f "${BUILD_DB_DIR}/build.db-shm" || -f "${BUILD_DB_DIR}/build.db-wal" ]]; then
  die "Detected active or stale Xcode build database lock at ${BUILD_DB_DIR}. Stop other builds and retry."
fi

step "1/4" "Clearing xattrs from app source paths"
xattr -rc macos/Runner assets lib pubspec.yaml pubspec.lock || true

# Best-effort cleanup for previously built app bundle.
if [[ -d "$APP_BUNDLE_PATH" ]]; then
  info "Clearing xattrs from existing app bundle"
  xattr -rc "$APP_BUNDLE_PATH" || true
fi

if [[ "$SKIP_BUILD" == "1" ]]; then
  step "2/4" "Skipping app build and reusing existing bundle"
  [[ -d "$APP_BUNDLE_PATH" ]] || die "Expected app bundle for --skip-build: $APP_BUNDLE_PATH"
  info "Using existing app bundle: $APP_BUNDLE_PATH"
else
  step "2/4" "Building macOS Release app (xcodebuild, signing disabled)"
  info "This can take a few minutes..."
  BUILD_LOG_FILE="$(mktemp -t venera-macos-build.XXXXXX.log)"
  if [[ "$VERBOSE" == "1" ]]; then
    (
      cd macos
      xcodebuild \
        -workspace Runner.xcworkspace \
        -scheme Runner \
        -configuration Release \
        -destination "$XCODE_DESTINATION" \
        -derivedDataPath ../build/macos \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        VENERA_RUNTIME_ROOT_OVERRIDE="$DEV_RUNTIME_ROOT_OVERRIDE" \
        build
    )
  else
    start_spinner "xcodebuild in progress"
    if (
      cd macos
      xcodebuild \
        -quiet \
        -workspace Runner.xcworkspace \
        -scheme Runner \
        -configuration Release \
        -destination "$XCODE_DESTINATION" \
        -derivedDataPath ../build/macos \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        VENERA_RUNTIME_ROOT_OVERRIDE="$DEV_RUNTIME_ROOT_OVERRIDE" \
        build >"$BUILD_LOG_FILE" 2>&1
    ); then
      stop_spinner
      info "Build completed"
      if [[ "$KEEP_LOGS" != "1" ]]; then
        rm -f "$BUILD_LOG_FILE"
        BUILD_LOG_FILE=""
      fi
    else
      stop_spinner
      printf "\n[ERROR] xcodebuild failed. Raw output:\n" >&2
      cat "$BUILD_LOG_FILE" >&2
      if [[ "$KEEP_LOGS" != "1" ]]; then
        rm -f "$BUILD_LOG_FILE"
      fi
      exit 1
    fi
  fi
fi

[[ -d "$APP_BUNDLE_PATH" ]] || die "Build succeeded but app bundle not found: $APP_BUNDLE_PATH"

if [[ "$CREATE_DMG" == "1" ]]; then
  step "3/4" "Preparing DMG staging directory"
  mkdir -p "$DMG_STAGE_DIR"
  rm -rf "${DMG_STAGE_DIR}/${APP_NAME}.app" "${DMG_STAGE_DIR}/Applications"
  ditto "$APP_BUNDLE_PATH" "${DMG_STAGE_DIR}/${APP_NAME}.app"
  ln -s /Applications "${DMG_STAGE_DIR}/Applications"
  info "Staged app: ${DMG_STAGE_DIR}/${APP_NAME}.app"

  step "4/4" "Creating DMG image"
  rm -f "$DMG_OUTPUT_PATH"
  DMG_LOG_FILE="$(mktemp -t venera-dmg-create.XXXXXX.log)"
  start_spinner "hdiutil creating DMG"
  if hdiutil create \
    -quiet \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT_PATH" >"$DMG_LOG_FILE" 2>&1; then
    stop_spinner
    info "DMG image creation completed"
    if [[ "$WRITE_CHECKSUM" == "1" ]]; then
      shasum -a 256 "$DMG_OUTPUT_PATH" > "$DMG_SHA256_PATH"
      info "SHA-256 checksum written: $DMG_SHA256_PATH"
    else
      rm -f "$DMG_SHA256_PATH" || true
    fi
    if [[ "$KEEP_LOGS" != "1" ]]; then
      rm -f "$DMG_LOG_FILE"
      DMG_LOG_FILE=""
    fi
  else
    stop_spinner
    printf "\n[ERROR] hdiutil failed. Raw output:\n" >&2
    cat "$DMG_LOG_FILE" >&2
    if [[ "$KEEP_LOGS" != "1" ]]; then
      rm -f "$DMG_LOG_FILE"
    fi
    exit 1
  fi

  [[ -f "$DMG_OUTPUT_PATH" ]] || die "DMG creation completed but output file is missing"
  SIZE="$(du -h "$DMG_OUTPUT_PATH" | awk '{print $1}')"
  ARTIFACT_PATH="$DMG_OUTPUT_PATH"
  ARTIFACT_KIND="DMG"
  CHECKSUM_PATH="$DMG_SHA256_PATH"
else
  ARTIFACT_PATH="$APP_BUNDLE_PATH"
  ARTIFACT_KIND="app bundle"
  CHECKSUM_PATH=""
  SIZE="$(du -sh "$APP_BUNDLE_PATH" | awk '{print $1}')"
fi
END_TS="$(date +%s)"
ELAPSED="$((END_TS - START_TS))"

printf "\n[SUCCESS] macOS %s created.\n" "$ARTIFACT_KIND"
printf "  Path: %s\n" "$ARTIFACT_PATH"
printf "  Size: %s\n" "$SIZE"
if [[ -n "${CHECKSUM_PATH:-}" && -f "$CHECKSUM_PATH" ]]; then
  printf "  SHA-256: %s\n" "$CHECKSUM_PATH"
fi
printf "  Time: %ss\n" "$ELAPSED"
printf "  Tip:  Open with Finder or run: open \"%s\"\n" "$ARTIFACT_PATH"

if [[ "$OPEN_AFTER_BUILD" == "1" ]]; then
  open "$ARTIFACT_PATH"
fi
