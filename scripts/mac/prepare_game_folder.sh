#!/usr/bin/env bash
# Mac: turns your game .pkg and 1.09 update .pkg into one folder (base + update merged), with the
# ps4-pkg-tool you already have. The folder is what build_recomp_ios.sh reads, and what the app's
# "Choose folder" takes.
#   scripts/mac/prepare_game_folder.sh PKG_TOOL BASE.pkg UPDATE.pkg OUT_DIR
set -euo pipefail
[[ $# -eq 4 ]] || { sed -n '2,6p' "$0"; exit 1; }
TOOL=$1 BASE=$2 UPDATE=$3 OUT=$4
mkdir -p "$OUT/base" "$OUT/update" "$OUT/merged"
"$TOOL" "$BASE" "$OUT/base"
"$TOOL" "$UPDATE" "$OUT/update"
root() { dirname "$(dirname "$(find "$1" -path '*sce_sys/param.sfo' -print -quit)")"; }
B=$(root "$OUT/base"); U=$(root "$OUT/update")
[[ -d $B && -d $U ]] || { echo "No sce_sys/param.sfo found in the extracted packages." >&2; exit 1; }
rsync -a "$B/" "$OUT/merged/"
rsync -a "$U/" "$OUT/merged/"
echo "Merged game folder: $OUT/merged"
