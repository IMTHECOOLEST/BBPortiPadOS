#!/usr/bin/env bash
# macOS + Xcode: builds the vendored ps4-pkg-tools core (PKG extraction) for iPadOS into
# Vendor/pkgtool (lib/libpkgtool.a and include/pkg_tool/lib.h). Needs network for cryptopp and zlib.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
SRC=$ROOT/third_party/ps4-pkg-tools
WORK=$ROOT/Vendor/pkgtool-build
OUT=$ROOT/Vendor/pkgtool
LOGS=$ROOT/Vendor/logs
rm -rf "$WORK"; mkdir -p "$WORK" "$OUT/lib" "$OUT/include/pkg_tool" "$LOGS"
# A writable copy with the external libraries the project's .gitmodules names.
cp -R "$SRC" "$WORK/src-tree"
T=$WORK/src-tree
mkdir -p "$T/externals"
clone() { rm -rf "$T/externals/$1"; git clone -q --depth 1 "$2" "$T/externals/$1"; }
clone cryptopp https://github.com/shadps4-emu/ext-cryptopp.git
clone cryptopp-cmake https://github.com/shadps4-emu/ext-cryptopp-cmake.git
clone zlib https://github.com/madler/zlib.git

# BUILD_PKG_CLI=OFF: the command-line tool is a macOS program. With CMAKE_SYSTEM_NAME=iOS CMake
# makes every executable a MACOSX_BUNDLE, and the project's install(TARGETS ps4-pkg-tool RUNTIME
# ...) then stops generation ("install TARGETS given no BUNDLE DESTINATION"). The app only needs
# the static core library. zlib's generated zconf.h lives in its build directory: put it on the
# include path so that zlib/zlib.h finds it whichever zlib release is cloned.
if ! cmake -S "$T" -B "$WORK/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DBUILD_PKG_CLI=OFF -DBUILD_PKG_QT_GUI=OFF \
  -DCMAKE_CXX_FLAGS="-I$WORK/build/externals/zlib" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 > "$LOGS/pkgtool-configure.log" 2>&1; then
  tail -60 "$LOGS/pkgtool-configure.log" >&2
  echo "ps4-pkg-tools: CMake configure failed (Vendor/logs/pkgtool-configure.log)" >&2
  exit 1
fi
# -k 0: keep going after a failure, so one run lists every error.
if ! cmake --build "$WORK/build" --target ps4_pkg_tool_core -- -k 0 > "$LOGS/pkgtool-build.log" 2>&1; then
  grep -n -m 40 -E 'error:|fatal error:|FAILED:' "$LOGS/pkgtool-build.log" >&2 || true
  tail -20 "$LOGS/pkgtool-build.log" >&2
  echo "ps4-pkg-tools: build failed (Vendor/logs/pkgtool-build.log)" >&2
  exit 1
fi
# One archive: the core, cryptopp and zlib. (No mapfile: macOS ships bash 3.2.)
libs=()
while IFS= read -r lib; do libs+=("$lib"); done < <(find "$WORK/build" -name '*.a' | sort)
[[ ${#libs[@]} -gt 0 ]] || { echo "ps4-pkg-tools: no static libraries were built" >&2; exit 1; }
libtool -static -o "$OUT/lib/libpkgtool.a" "${libs[@]}"
cp "$T/src/pkg_tool/lib.h" "$OUT/include/pkg_tool/lib.h"
echo "Done: $OUT (${#libs[@]} archives merged)"
