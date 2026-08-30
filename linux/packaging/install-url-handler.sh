#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app_path="$script_dir/mirushin"
if [ ! -x "$app_path" ]; then
  echo "MiruShin executable not found beside this script." >&2
  exit 1
fi

single_line_app_path=$(printf '%s' "$app_path" | tr -d '\r\n')
if [ "$single_line_app_path" != "$app_path" ]; then
  echo "The MiruShin path contains an unsupported newline." >&2
  exit 1
fi

data_home=${XDG_DATA_HOME:-"${HOME:?HOME is required}/.local/share"}
applications_dir="$data_home/applications"
desktop_file="$applications_dir/com.emp0ry.mirushin.desktop"
escaped_app=$(printf '%s' "$app_path" | sed 's/[\\`"$]/\\&/g')
expected_exec="Exec=\"$escaped_app\" %u"

refresh_desktop_database() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q "$applications_dir" >/dev/null 2>&1 || true
  fi
}

if [ "${1:-}" = "--remove" ]; then
  if [ -f "$desktop_file" ] && grep -Fqx -- "$expected_exec" "$desktop_file"; then
    rm -f -- "$desktop_file"
    refresh_desktop_database
    echo "Removed this MiruShin portable URL-handler registration."
  else
    echo "The current URL handler belongs to another MiruShin installation; it was left unchanged."
  fi
  exit 0
fi

mkdir -p -- "$applications_dir"
temporary_file=$(mktemp "${desktop_file}.tmp.XXXXXX")
trap 'rm -f -- "$temporary_file"' EXIT HUP INT TERM
{
  printf '%s\n' '[Desktop Entry]'
  printf '%s\n' 'Type=Application'
  printf '%s\n' 'Name=MiruShin'
  printf '%s\n' "$expected_exec"
  printf '%s\n' "Icon=$script_dir/data/logo.png"
  printf '%s\n' 'Categories=AudioVideo;'
  printf '%s\n' 'MimeType=x-scheme-handler/mirushin;'
  printf '%s\n' 'StartupWMClass=MiruShin'
  printf '%s\n' 'Terminal=false'
} > "$temporary_file"
chmod 0644 "$temporary_file"
mv -f -- "$temporary_file" "$desktop_file"
trap - EXIT HUP INT TERM

if command -v xdg-mime >/dev/null 2>&1; then
  xdg-mime default com.emp0ry.mirushin.desktop x-scheme-handler/mirushin || true
fi
refresh_desktop_database
echo "Registered mirushin:// links for $app_path"
