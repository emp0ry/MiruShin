#!/usr/bin/env bash
set -euo pipefail

readonly PACKAGE_VERSION="0.1.0-beta.1"
readonly PACKAGE_ROOT="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev/flutter_inappwebview_linux-${PACKAGE_VERSION}"
readonly SOURCE_RELATIVE="linux/CMakeLists.txt"
readonly SOURCE_FILE="${PACKAGE_ROOT}/${SOURCE_RELATIVE}"
readonly COMPILER_PATCH_MARKER='CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL 17'
readonly WPE_PATCH_MARKER='find_and_add_library("${WPE_WEBKIT_LIBRARY_BASENAME}"'
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PATCH_FILE="${SCRIPT_DIR}/../patches/flutter_inappwebview_linux-ubuntu22.patch"

if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "ERROR: flutter_inappwebview_linux ${PACKAGE_VERSION} source not found at ${SOURCE_FILE}" >&2
  exit 1
fi

if grep -Fq "$COMPILER_PATCH_MARKER" "$SOURCE_FILE" &&
   grep -Fq "$WPE_PATCH_MARKER" "$SOURCE_FILE"; then
  echo "flutter_inappwebview_linux ${PACKAGE_VERSION} already patched for Ubuntu 22.04"
  exit 0
fi

git -C "$PACKAGE_ROOT" apply -p2 "$PATCH_FILE"

if ! grep -Fq "$COMPILER_PATCH_MARKER" "$SOURCE_FILE" ||
   ! grep -Fq "$WPE_PATCH_MARKER" "$SOURCE_FILE"; then
  echo "ERROR: flutter_inappwebview_linux Ubuntu 22.04 patch was not applied" >&2
  exit 1
fi

echo "Patched flutter_inappwebview_linux ${PACKAGE_VERSION} for Ubuntu 22.04"
