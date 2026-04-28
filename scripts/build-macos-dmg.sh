#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="venera"
APP_BUNDLE_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
DMG_STAGE_DIR="dist/dmg_contents"
DMG_OUTPUT_PATH="dist/${APP_NAME}.dmg"
START_TS="$(date +%s)"
VERBOSE="${VERBOSE:-0}"
DMG_LOG_FILE=""
BUILD_LOG_FILE=""

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
  printf "\n[FAILED] DMG build stopped (exit=%s).\n" "$exit_code" >&2
  printf "         Check the step logs above for the first failing command.\n" >&2
}
trap on_error ERR

cleanup_temp_files() {
  stop_spinner
  [[ -n "$DMG_LOG_FILE" ]] && rm -f "$DMG_LOG_FILE" || true
  [[ -n "$BUILD_LOG_FILE" ]] && rm -f "$BUILD_LOG_FILE" || true
}

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

step "PRECHECK" "Validating required tools and paths"
require_cmd xattr
require_cmd xcodebuild
require_cmd hdiutil
[[ -d "macos" ]] || die "Missing macos/ directory"
[[ -f "macos/Runner.xcworkspace/contents.xcworkspacedata" ]] || die "Missing Runner.xcworkspace"
info "Workspace: $ROOT_DIR"
info "Output DMG: $DMG_OUTPUT_PATH"

step "1/4" "Clearing xattrs from app source paths"
xattr -rc macos/Runner assets lib pubspec.yaml pubspec.lock || true

# Best-effort cleanup for previously built app bundle.
if [[ -d "$APP_BUNDLE_PATH" ]]; then
  info "Clearing xattrs from existing app bundle"
  xattr -rc "$APP_BUNDLE_PATH" || true
fi

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
      -derivedDataPath ../build/macos \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
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
      -derivedDataPath ../build/macos \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      build >"$BUILD_LOG_FILE" 2>&1
  ); then
    stop_spinner
    info "Build completed"
    rm -f "$BUILD_LOG_FILE"
    BUILD_LOG_FILE=""
  else
    stop_spinner
    printf "\n[ERROR] xcodebuild failed. Raw output:\n" >&2
    cat "$BUILD_LOG_FILE" >&2
    rm -f "$BUILD_LOG_FILE"
    BUILD_LOG_FILE=""
    exit 1
  fi
fi

[[ -d "$APP_BUNDLE_PATH" ]] || die "Build succeeded but app bundle not found: $APP_BUNDLE_PATH"

step "3/4" "Preparing DMG staging directory"
mkdir -p "$DMG_STAGE_DIR"
rm -rf "${DMG_STAGE_DIR}/${APP_NAME}.app" "${DMG_STAGE_DIR}/Applications"
cp -R "$APP_BUNDLE_PATH" "$DMG_STAGE_DIR/"
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
  rm -f "$DMG_LOG_FILE"
  DMG_LOG_FILE=""
else
  stop_spinner
  printf "\n[ERROR] hdiutil failed. Raw output:\n" >&2
  cat "$DMG_LOG_FILE" >&2
  rm -f "$DMG_LOG_FILE"
  DMG_LOG_FILE=""
  exit 1
fi

[[ -f "$DMG_OUTPUT_PATH" ]] || die "DMG creation completed but output file is missing"
END_TS="$(date +%s)"
ELAPSED="$((END_TS - START_TS))"
SIZE="$(du -h "$DMG_OUTPUT_PATH" | awk '{print $1}')"

printf "\n[SUCCESS] DMG created.\n"
printf "  Path: %s\n" "$DMG_OUTPUT_PATH"
printf "  Size: %s\n" "$SIZE"
printf "  Time: %ss\n" "$ELAPSED"
printf "  Tip:  Open with Finder or run: open \"%s\"\n" "$DMG_OUTPUT_PATH"

cleanup_temp_files
