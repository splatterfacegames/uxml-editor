#!/usr/bin/env bash
# Record the announcement reel (src/app/reel.gd) with Godot's Movie Maker:
# a fixed timeline at a fixed 60 fps, 1920x1080, one PNG per frame. The
# window is small, without focus, at the bottom right of the screen (the
# frames come from the 1920x1080 viewport, not from the window).
#
#   GODOT=<godot 4.7.1> tools/record_reel.sh <out dir>
#
# Writes <out dir>/editor/frame########.png. A temporary override.cfg sets
# the Movie Maker size; it is removed afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="${1:?out dir}"
POS="${REEL_POSITION:-2160,1160}"

test ! -e override.cfg || { echo "override.cfg exists; not touching it" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -f override.cfg; rm -rf "$TMP"' EXIT
cat > override.cfg <<'CFG'
[display]

window/size/viewport_width=1920
window/size/viewport_height=1080
window/size/no_focus=true
CFG
rm -rf "$OUT/editor"
mkdir -p "$OUT/editor"
"$GODOT" --path . --position "$POS" --resolution 384x216 --fixed-fps 60 --quit-after 1200 \
  --write-movie "$OUT/editor/frame.png" -- --reel --watch-interval=0 \
  "--settings=$TMP/settings.cfg" "--recovery-dir=$TMP/recovery"
