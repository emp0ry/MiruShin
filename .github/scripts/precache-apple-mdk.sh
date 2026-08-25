#!/usr/bin/env bash
set -euo pipefail

readonly MDK_VERSION="0.36.0"
readonly MDK_SF_URL="https://sourceforge.net/projects/mdk-sdk/files/nightly/mdk-sdk-apple.tar.xz"
readonly MDK_GH_URL="https://github.com/wang-bin/mdk-sdk/releases/download/v${MDK_VERSION}/mdk-sdk-apple.tar.xz"
readonly MDK_SPEC_URL="https://cdn.cocoapods.org/Specs/5/1/3/mdk/${MDK_VERSION}/mdk.podspec.json"
readonly TEMP_DIR="${RUNNER_TEMP:-/tmp}"
readonly ARCHIVE="${TEMP_DIR}/mdk-sdk-apple-${MDK_VERSION}.tar.xz"
readonly SPEC_FILE="${TEMP_DIR}/mdk-${MDK_VERSION}.podspec.json"

cleanup() {
  rm -f "$ARCHIVE" "$SPEC_FILE"
}
trap cleanup EXIT

# CocoaPods requires both the extracted pod and its cached specification. Its
# cache slug includes the source parameters and the podspec checksum, so use
# CocoaPods itself to calculate the exact paths instead of duplicating that
# internal algorithm.
echo "Downloading mdk ${MDK_VERSION} podspec"
curl -fL --retry 4 --retry-delay 2 --retry-all-errors \
  -o "$SPEC_FILE" "$MDK_SPEC_URL"

CACHE_METADATA=$(ruby -rcocoapods -e '
  spec = Pod::Specification.from_file(ARGV.fetch(0))
  abort "unexpected mdk podspec" unless spec.name == "mdk" && spec.version.to_s == ARGV.fetch(1)
  abort "unexpected mdk source URL" unless spec.source[:http] == ARGV.fetch(2)
  request = Pod::Downloader::Request.new(spec: spec, released: false)
  cache = Pod::Downloader::Cache.new(Pod::Config.instance.cache_root + "Pods")
  slug = request.slug
  puts [cache.root, (cache.root + slug), (cache.root + "Specs" + "#{slug}.podspec.json")].join("\t")
' "$SPEC_FILE" "$MDK_VERSION" "$MDK_SF_URL")
IFS=$'\t' read -r CACHE_ROOT CACHE_DIR SPEC_CACHE <<< "$CACHE_METADATA"

if [[ -z "$CACHE_ROOT" || "$CACHE_ROOT" != */Pods ||
      "$CACHE_DIR" != "$CACHE_ROOT"/External/mdk/* ||
      "$SPEC_CACHE" != "$CACHE_ROOT"/Specs/External/mdk/*.podspec.json ]]; then
  echo "ERROR: CocoaPods returned unsafe or unexpected mdk cache paths" >&2
  exit 1
fi

if [ -d "$CACHE_DIR" ] &&
   [ -e "$CACHE_DIR/mdk-sdk/lib/mdk.xcframework" ] &&
   [ -f "$SPEC_CACHE" ]; then
  echo "mdk SDK already cached at $CACHE_DIR"
  exit 0
fi

rm -rf "$CACHE_DIR"
rm -f "$SPEC_CACHE" "$ARCHIVE"
mkdir -p "$CACHE_DIR" "$(dirname "$SPEC_CACHE")"

downloaded=0
for url in "$MDK_GH_URL" "${MDK_SF_URL}/download"; do
  echo "Downloading mdk SDK from $url"
  if curl -fL --retry 4 --retry-delay 2 --retry-all-errors -o "$ARCHIVE" "$url"; then
    if [ "$(wc -c < "$ARCHIVE")" -gt 1048576 ] && tar tf "$ARCHIVE" >/dev/null; then
      downloaded=1
      break
    fi
    echo "Downloaded archive from $url failed validation"
  else
    echo "Download failed from $url"
  fi
  rm -f "$ARCHIVE"
done

if [ "$downloaded" -ne 1 ]; then
  rm -rf "$CACHE_DIR"
  rm -f "$SPEC_CACHE"
  echo "ERROR: unable to download a valid mdk-sdk-apple.tar.xz archive" >&2
  exit 1
fi

tar xf "$ARCHIVE" -C "$CACHE_DIR"
cp "$SPEC_FILE" "$SPEC_CACHE"

if [ ! -e "$CACHE_DIR/mdk-sdk/lib/mdk.xcframework" ] ||
   [ ! -f "$SPEC_CACHE" ]; then
  rm -rf "$CACHE_DIR"
  rm -f "$SPEC_CACHE"
  echo "ERROR: CocoaPods mdk cache entry is incomplete" >&2
  exit 1
fi

echo "Cached mdk SDK and podspec at $CACHE_DIR"
