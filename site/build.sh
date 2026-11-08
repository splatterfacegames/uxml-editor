#!/usr/bin/env bash
# Build https://uxml-editor.splatterfacegames.com into site/dist:
# the Web export of the editor (preset "Web": GDScript path, Compatibility
# renderer, no threads) in site/dist/editor, the sample project in
# site/dist/editor/samples/sample.zip, and the page from site/public.
# Files over the Pages limit move to site/.r2-upload.
#
#   GODOT=<godot 4.7.1> site/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

rm -rf site/dist site/.r2-upload
mkdir -p site/dist/editor

# The first import after a checkout can crash; a second one passes.
"$GODOT" --headless --path . --import || "$GODOT" --headless --path . --import
"$GODOT" --headless --path . --export-release Web site/dist/editor/index.html
test -s site/dist/editor/index.pck

python3 site/make_sample.py site/dist/editor/samples/sample.zip
cp -R site/public/. site/dist/
node site/prepare_r2_assets.mjs site/dist site/.r2-upload
