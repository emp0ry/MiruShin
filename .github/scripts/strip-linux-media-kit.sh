#!/usr/bin/env bash
set -euo pipefail

cmake_file="linux/flutter/generated_plugins.cmake"
registrant_file="linux/flutter/generated_plugin_registrant.cc"

if [[ -f "$cmake_file" ]]; then
  perl -0pi -e 's/\n  media_kit_video(?=\n)//g' "$cmake_file"
fi

if [[ -f "$registrant_file" ]]; then
  perl -0pi -e 's/#include <media_kit_video\/media_kit_video_plugin\.h>\n//g; s/\n  g_autoptr\(FlPluginRegistrar\) media_kit_video_registrar =\n      fl_plugin_registry_get_registrar_for_plugin\(registry, "MediaKitVideoPlugin"\);\n  media_kit_video_plugin_register_with_registrar\(media_kit_video_registrar\);//g' "$registrant_file"
fi
