#!/usr/bin/env bash
# Mac: builds the recompiled game library for iPadOS from YOUR game folder (base + 1.09 update).
# The library is made from your copy of the game: keep it on your machines, never publish it, and
# never commit it (Vendor/ is in .gitignore).
#   scripts/mac/build_recomp_ios.sh /path/to/CUSA03173
# Output: Vendor/recomp/librecomp.dylib (about 400 MB, 10-20 minutes). Needs Xcode, clang, cmake,
# ninja and Python 3. Then put it into the app with scripts/mac/embed_recomp.sh (an IPA) or let
# the Xcode build embed it (scripts/ios/embed_libs.sh does it when the file exists).
set -euo pipefail
[[ $# -eq 1 ]] || { sed -n '2,10p' "$0"; exit 1; }
GAME=$(cd "$1" && pwd)
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RECOMP=${RECOMP_DIR:-$ROOT/Vendor/recomp-src}
if [[ ! -d $RECOMP/src/cpu ]]; then
  git clone --depth 1 "${RECOMP_REPO:-https://github.com/bloodborne-native/bloodborne-recomp.git}" "$RECOMP"
fi
cd "$RECOMP"
for p in "$ROOT"/patches/recomp/*.patch; do
  if patch -p1 --dry-run -s < "$p" >/dev/null 2>&1; then patch -p1 -s < "$p"; echo "patched: $(basename "$p")"
  elif patch -R -p1 --dry-run -s < "$p" >/dev/null 2>&1; then echo "already applied: $(basename "$p")"
  else echo "PATCH DOES NOT APPLY: $(basename "$p") (the upstream source changed; update the patch)" >&2; exit 1; fi
done
[[ -f $GAME/eboot.bin ]] || { echo "No eboot.bin in $GAME" >&2; exit 1; }
./build.sh                                   # host tools: bbcpu, scan, bbrecomp, Zydis
python3 tools/recomp/ps4elf.py "$GAME/eboot.bin" out/eboot.elf
python3 tools/recomp/pointers.py "$GAME/eboot.bin" out/recomp/pointers.txt
out/recomp/scan out/eboot.elf out/recomp out/recomp/pointers.txt
python3 tools/recomp/imports.py "$GAME/eboot.bin" out/recomp
tail -n +2 out/recomp/functions.tsv | cut -f1 > out/recomp/all.txt
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
export TARGET_FLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=17.0"
tools/recomp/recomp.sh --file out/recomp/all.txt
mkdir -p "$ROOT/Vendor/recomp"
cp out/recomp/librecomp.dylib "$ROOT/Vendor/recomp/librecomp.dylib"
lipo -info "$ROOT/Vendor/recomp/librecomp.dylib"
vtool -show-build "$ROOT/Vendor/recomp/librecomp.dylib" | head -8 || true
echo "Done: $ROOT/Vendor/recomp/librecomp.dylib"
