#!/usr/bin/env bash
# Mac: puts your librecomp.dylib into a built IPA (Payload/Bloodborne.app/Frameworks). Sign the
# result with your own tool (Sideloadly, AltStore, Xcode's devicectl...): they sign everything
# inside the bundle.
#   scripts/mac/embed_recomp.sh Bloodborne.ipa Vendor/recomp/librecomp.dylib [Out.ipa]
set -euo pipefail
[[ $# -ge 2 ]] || { sed -n '2,6p' "$0"; exit 1; }
IPA=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); LIB=$2; OUT=${3:-${IPA%.ipa}-recomp.ipa}
case $OUT in /*) ;; *) OUT=$PWD/$OUT;; esac
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
unzip -q "$IPA" -d "$W"
APP=$(find "$W/Payload" -maxdepth 1 -name '*.app' | head -1)
mkdir -p "$APP/Frameworks"
cp "$LIB" "$APP/Frameworks/librecomp.dylib"
(cd "$W" && rm -f "$OUT" && zip -qry "$OUT" Payload)
echo "Wrote $OUT"
