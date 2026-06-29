#!/usr/bin/env bash
#
# Build an unsigned iOS .ipa locally on macOS, mirroring .github/workflows/build-ios.yml.
#
# The produced .ipa is NOT code-signed — it is meant for sideloading tools
# (AltStore/SideStore, etc.) that re-sign on install, the same as the CI artifact.
#
# Usage:
#   ./package-ios-ipa.sh           # build + package
#   ./package-ios-ipa.sh --gen     # also regenerate envied sources (env.g.dart)
#   ./package-ios-ipa.sh --clean   # flutter clean before building
#
set -euo pipefail

APP_NAME="MiruShin"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

GEN_ENV=false
DO_CLEAN=false
for arg in "$@"; do
  case "$arg" in
    --gen) GEN_ENV=true ;;
    --clean) DO_CLEAN=true ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

# --- Sanity checks --------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: iOS builds require macOS." >&2
  exit 1
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: 'flutter' not found in PATH." >&2
  exit 1
fi
if [[ ! -f .env ]]; then
  echo "ERROR: .env is missing. It is gitignored; create it with at least:" >&2
  echo "  TMDB_READ_ACCESS_TOKEN=<token>" >&2
  echo "  MODULE_LIBRARY_URL=<url>" >&2
  exit 1
fi

# --- No-codesign xcconfig (restored on exit so the tree stays clean) ------
XCCONFIG="ios/Flutter/Release.xcconfig"
BACKUP="$(mktemp)"
cp "$XCCONFIG" "$BACKUP"
restore_xcconfig() {
  cp "$BACKUP" "$XCCONFIG"
  rm -f "$BACKUP"
}
trap restore_xcconfig EXIT

{
  echo ""
  echo "CODE_SIGN_ENTITLEMENTS="
  echo "DEVELOPMENT_TEAM="
  echo "PROVISIONING_PROFILE_SPECIFIER="
  echo "CODE_SIGN_STYLE=Manual"
} >> "$XCCONFIG"

# --- Build ----------------------------------------------------------------
if [[ "$DO_CLEAN" == true ]]; then
  echo "==> flutter clean"
  flutter clean
fi

echo "==> flutter pub get"
flutter pub get

if [[ "$GEN_ENV" == true || ! -f lib/core/env/env.g.dart ]]; then
  echo "==> Generating envied sources (build_runner)"
  dart run build_runner build --delete-conflicting-outputs
fi

echo "==> flutter build ios --release --no-codesign"
flutter build ios --release --no-codesign

# --- Package --------------------------------------------------------------
VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)"
APP_PATH="build/ios/iphoneos/Runner.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: iOS app not found at $APP_PATH" >&2
  ls -la build/ios/iphoneos || true
  exit 1
fi

OUT_DIR="$ROOT_DIR/dist"
mkdir -p "$OUT_DIR"
IPA_PATH="$OUT_DIR/${APP_NAME}-ios-v${VERSION}.ipa"

WORK="$(mktemp -d)"
mkdir -p "$WORK/Payload"
cp -R "$APP_PATH" "$WORK/Payload/"
rm -f "$IPA_PATH"
( cd "$WORK" && zip -qr "$IPA_PATH" Payload )
rm -rf "$WORK"

echo ""
echo "==> Done."
echo "IPA: $IPA_PATH ($(du -h "$IPA_PATH" | cut -f1))"
