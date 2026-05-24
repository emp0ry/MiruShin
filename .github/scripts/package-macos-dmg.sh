#!/usr/bin/env bash
set -e

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)

APP_SRC=""
for candidate in \
  "build/macos/Build/Products/Release-dev/mirushin.app" \
  "build/macos/Build/Products/Release-dev/MiruShin.app" \
  "build/macos/Build/Products/Release/mirushin.app" \
  "build/macos/Build/Products/Release/MiruShin.app"; do
  if [ -d "$candidate" ]; then
    APP_SRC="$candidate"
    break
  fi
done

if [ -z "$APP_SRC" ]; then
  echo "ERROR: macOS app not found"
  ls -la build/macos/Build/Products/Release-dev || true
  ls -la build/macos/Build/Products/Release || true
  exit 1
fi

STAGE_DIR="build/macos/dmg/MiruShin"
rm -rf "build/macos/dmg"
mkdir -p "$STAGE_DIR"

ENTITLEMENTS_FILE="macos/Runner/Release.entitlements"
if [ ! -f "$ENTITLEMENTS_FILE" ]; then
  echo "ERROR: entitlements file not found at $ENTITLEMENTS_FILE"
  exit 1
fi

cp -R "$APP_SRC" "$STAGE_DIR/MiruShin.app"
APP_BUNDLE="$STAGE_DIR/MiruShin.app"

if [ -d "$APP_BUNDLE/Contents/Frameworks" ]; then
  find "$APP_BUNDLE/Contents/Frameworks" -type d -name "*.framework" -print0 \
    | while IFS= read -r -d '' fw; do
        codesign --force --sign - "$fw" || true
      done
  find "$APP_BUNDLE/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "*.so" \) -print0 \
    | while IFS= read -r -d '' lib; do
        codesign --force --sign - "$lib" || true
      done
fi

codesign --force --sign - --entitlements "$ENTITLEMENTS_FILE" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

ENTITLEMENTS_DUMP=$(mktemp)
codesign -d --entitlements :- "$APP_BUNDLE" > "$ENTITLEMENTS_DUMP" 2>/dev/null
if ! grep -q "com.apple.security.files.user-selected.read-write" "$ENTITLEMENTS_DUMP"; then
  echo "ERROR: staged macOS app is missing user-selected file access entitlements"
  cat "$ENTITLEMENTS_DUMP"
  exit 1
fi

ln -s /Applications "$STAGE_DIR/Applications"

RW_DMG="build/macos/dmg/MiruShin-temp.dmg"
DMG_NAME="MiruShin-macos-v${VERSION}.dmg"
rm -f "$RW_DMG" "$DMG_NAME"

hdiutil create \
  -volname "MiruShin" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDRW \
  -fs HFS+ \
  "$RW_DMG"

ATTACH_OUTPUT=$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)
DEVICE=$(echo "$ATTACH_OUTPUT" | awk '/\/Volumes\/MiruShin/{print $1; exit}')
if [ -z "$DEVICE" ]; then
  echo "ERROR: failed to mount temporary DMG"
  echo "$ATTACH_OUTPUT"
  exit 1
fi

osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "MiruShin"
    open
    tell container window
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set bounds to {140, 140, 640, 360}
    end tell
    tell icon view options of container window
      set arrangement to not arranged
      set icon size to 88
      set text size to 13
    end tell
    set position of item "MiruShin.app" of container window to {140, 95}
    set position of item "Applications" of container window to {360, 95}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$DEVICE"

hdiutil convert \
  "$RW_DMG" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_NAME"

rm -f "$RW_DMG"

echo "Created $DMG_NAME"
