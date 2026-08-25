#!/usr/bin/env bash
set -euo pipefail

readonly PACKAGE_VERSION="1.1.2"
readonly PACKAGE_ROOT="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev/flutter_inappwebview_macos-${PACKAGE_VERSION}"
readonly SOURCE_RELATIVE="macos/Classes/WebAuthenticationSession/WebAuthenticationSession.swift"
readonly SOURCE_FILE="${PACKAGE_ROOT}/${SOURCE_RELATIVE}"
readonly PATCH_MARKER="private class WebAuthenticationPresentationContextProviding"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PATCH_FILE="${SCRIPT_DIR}/../patches/flutter_inappwebview_macos-xcode26.patch"

if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "ERROR: flutter_inappwebview_macos ${PACKAGE_VERSION} source not found at ${SOURCE_FILE}" >&2
  exit 1
fi

if grep -Fq "$PATCH_MARKER" "$SOURCE_FILE"; then
  echo "flutter_inappwebview_macos ${PACKAGE_VERSION} already patched for Xcode 26"
  exit 0
fi

patch -d "$PACKAGE_ROOT" -p2 < "$PATCH_FILE"

if ! grep -Fq "$PATCH_MARKER" "$SOURCE_FILE"; then
  echo "ERROR: flutter_inappwebview_macos Xcode 26 patch was not applied" >&2
  exit 1
fi

echo "Patched flutter_inappwebview_macos ${PACKAGE_VERSION} for Xcode 26"
