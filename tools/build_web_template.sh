#!/usr/bin/env bash
# Builds the slim Godot web export template (see web_template_profile.py).
# Needs: Godot source at $GODOT_SRC (tag 4.4.1-stable), emsdk 3.1.64 activated, scons.
# Output: build/templates/web_nothreads_release.zip (point the export preset's custom_template/release at it).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_SRC="${GODOT_SRC:?set GODOT_SRC to a Godot 4.4.1-stable checkout}"
cd "$GODOT_SRC"
scons profile="$ROOT/tools/web_template_profile.py" target=template_release -j"$(nproc)"
mkdir -p "$ROOT/build/templates"
cp bin/godot.web.template_release.wasm32.nothreads.zip "$ROOT/build/templates/web_nothreads_release.zip"
ls -la "$ROOT/build/templates"

# Optional: install it over the stock template so the normal "Web" export preset uses it.
if [ "${INSTALL:-0}" = "1" ]; then
  DEST="$HOME/.local/share/godot/export_templates/4.4.1.stable"
  mkdir -p "$DEST"
  cp "$ROOT/build/templates/web_nothreads_release.zip" "$DEST/web_nothreads_release.zip"
  echo "installed into $DEST"
fi
