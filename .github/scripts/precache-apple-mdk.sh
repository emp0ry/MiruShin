#!/usr/bin/env bash
set -euo pipefail

MDK_SF_URL="https://sourceforge.net/projects/mdk-sdk/files/nightly/mdk-sdk-apple.tar.xz"
MDK_GH_URL="https://github.com/wang-bin/mdk-sdk/releases/download/v0.36.0/mdk-sdk-apple.tar.xz"
ARCHIVE="/tmp/mdk-sdk-apple.tar.xz"

# CocoaPods caches HTTP pod downloads keyed by MD5({:http=>"url"}).
# Pre-populate the SourceForge cache entry with a verified archive so pod
# install does not fail on a transient mirror outage.
CACHE_HASH=$(ruby -rdigest -e 'puts Digest::MD5.hexdigest({:http=>ARGV[0]}.to_s)' "$MDK_SF_URL")
CACHE_DIR="$HOME/Library/Caches/CocoaPods/Pods/External/mdk/$CACHE_HASH"

if [ -d "$CACHE_DIR" ] && [ -e "$CACHE_DIR/mdk-sdk/lib/mdk.xcframework" ]; then
  echo "mdk SDK already cached at $CACHE_DIR"
  exit 0
fi

rm -rf "$CACHE_DIR" "$ARCHIVE"
mkdir -p "$CACHE_DIR"

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
  rm -rf "$CACHE_DIR" "$ARCHIVE"
  echo "ERROR: unable to download a valid mdk-sdk-apple.tar.xz archive" >&2
  exit 1
fi

tar xf "$ARCHIVE" -C "$CACHE_DIR"
rm -f "$ARCHIVE"

if [ ! -e "$CACHE_DIR/mdk-sdk/lib/mdk.xcframework" ]; then
  rm -rf "$CACHE_DIR"
  echo "ERROR: extracted mdk SDK did not contain mdk-sdk/lib/mdk.xcframework" >&2
  exit 1
fi

echo "Cached mdk SDK at $CACHE_DIR"
