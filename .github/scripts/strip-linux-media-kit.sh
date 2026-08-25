#!/usr/bin/env bash
set -euo pipefail

readonly cmake_file="linux/flutter/generated_plugins.cmake"
readonly registrant_file="linux/flutter/generated_plugin_registrant.cc"

if [[ ! -f "$cmake_file" || ! -f "$registrant_file" ]]; then
  echo "ERROR: Linux plugin files were not generated; run flutter pub get first" >&2
  exit 1
fi

perl -0pi -e 's/\r?\n  (?:flutter_inappwebview_linux|media_kit_video)(?=\r?\n)//g' "$cmake_file"

perl -0pi -e '
  s/#include <flutter_inappwebview_linux\/flutter_inappwebview_linux_plugin\.h>\r?\n//g;
  s/#include <media_kit_video\/media_kit_video_plugin\.h>\r?\n//g;
  s/\r?\n  g_autoptr\(FlPluginRegistrar\) flutter_inappwebview_linux_registrar =\r?\n      fl_plugin_registry_get_registrar_for_plugin\(registry, "FlutterInappwebviewLinuxPlugin"\);\r?\n  flutter_inappwebview_linux_plugin_register_with_registrar\(flutter_inappwebview_linux_registrar\);//g;
  s/\r?\n  g_autoptr\(FlPluginRegistrar\) media_kit_video_registrar =\r?\n      fl_plugin_registry_get_registrar_for_plugin\(registry, "MediaKitVideoPlugin"\);\r?\n  media_kit_video_plugin_register_with_registrar\(media_kit_video_registrar\);//g;
' "$registrant_file"

# MiruShin deliberately disables its flutter_inappwebview Cloudflare solver on
# Linux, and fvp is its Linux video backend. Neither stripped native plugin is
# used at runtime, so do not compile incompatible or duplicate implementations.
if grep -Eq 'flutter_inappwebview_linux|media_kit_video' "$cmake_file" "$registrant_file"; then
  echo "ERROR: unsupported Linux plugins were not fully stripped" >&2
  exit 1
fi

echo "Stripped unsupported flutter_inappwebview_linux and media_kit_video plugins"
