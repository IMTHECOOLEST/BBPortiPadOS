#!/usr/bin/env bash
# macOS + Xcode: builds the vendored ps4-pkg-tools core (PKG extraction) for iPadOS into
# Vendor/pkgtool (lib/libpkgtool.a and include/pkg_tool/lib.h). Needs network for cryptopp and zlib.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
SRC=$ROOT/third_party/ps4-pkg-tools
WORK=$ROOT/Vendor/pkgtool-build
OUT=$ROOT/Vendor/pkgtool
rm -rf "$WORK"; mkdir -p "$WORK" "$OUT/lib" "$OUT/include/pkg_tool"
# A writable copy with the external libraries the project's .gitmodules names.
cp -R "$SRC" "$WORK/src-tree"
T=$WORK/src-tree
mkdir -p "$T/externals"
clone() { rm -rf "$T/externals/$1"; git clone -q --depth 1 "$2" "$T/externals/$1"; }
clone cryptopp https://github.com/shadps4-emu/ext-cryptopp.git
clone cryptopp-cmake https://github.com/shadps4-emu/ext-cryptopp-cmake.git
clone zlib https://github.com/madler/zlib.git
cmake -S "$T" -B "$WORK/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DBUILD_PKG_QT_GUI=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5 >/dev/null
cmake --build "$WORK/build" --target ps4_pkg_tool_core
# One archive: the core, cryptopp and zlib.
mapfile -t libs < <(find "$WORK/build" -name '*.a' | sort)
libtool -static -o "$OUT/lib/libpkgtool.a" "${libs[@]}"
cp "$T/src/pkg_tool/lib.h" "$OUT/include/pkg_tool/lib.h"
echo "Done: $OUT"
