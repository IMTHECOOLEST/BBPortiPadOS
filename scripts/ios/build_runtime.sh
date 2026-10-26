#!/usr/bin/env bash
# macOS + Xcode: builds bloodborne-runtime for iPadOS into Vendor/runtime/lib:
#   libbbruntime.a  the runtime (src/*.c, bbcpu, Zydis, atrac9) as a static library, linked into the app
#   libbbgpu.dylib  the GPU library (shadPS4 video core), embedded in the app
# after scripts/ios/build_deps.sh. This is bloodborne-runtime's build.sh, translated.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
DEPS=$ROOT/Vendor/ios-deps
[[ -f $DEPS/.built-ffmpeg ]] || { echo "Run scripts/ios/build_deps.sh first." >&2; exit 1; }
SRC=${RUNTIME_DIR:-$ROOT/Vendor/runtime-src}
if [[ ! -d $SRC/src ]]; then
  git clone --recursive --depth 1 "${RUNTIME_REPO:-https://github.com/bloodborne-native/bloodborne-runtime.git}" "$SRC"
fi
cd "$SRC"
git submodule update --init --recursive >/dev/null 2>&1 || true
# This repo's changes to the runtime and to bbcpu (each applied once).
for p in "$ROOT"/patches/runtime/*.patch; do
  if patch -p1 --dry-run -s < "$p" >/dev/null 2>&1; then patch -p1 -s < "$p"; echo "patched: $(basename "$p")"; fi
done
( cd recomp && for p in "$ROOT"/patches/recomp/*.patch; do
    if patch -p1 --dry-run -s < "$p" >/dev/null 2>&1; then patch -p1 -s < "$p"; echo "patched (recomp): $(basename "$p")"; fi
  done )

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CC=(xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -isysroot "$SDK")
OUT=$SRC/out-ios
rm -rf "$OUT"; mkdir -p "$OUT/cpu" "$OUT/atrac9" "$OUT/rt"
export PKG_CONFIG_LIBDIR=$DEPS/lib/pkgconfig:$DEPS/share/pkgconfig
read -r -a inc <<< "$(pkg-config --cflags sdl3)"
NATIVE=$ROOT/App/Native

# bbcpu (the recompiled code's runtime and the interpreter; the translator stays off on iPadOS).
for f in recomp/src/cpu/*.c recomp/src/cpu/hostcall.S; do
  "${CC[@]}" -std=gnu11 -O2 -g -Wall -Wextra -Wno-unused-parameter -I"$DEPS/include" -c "$f" -o "$OUT/cpu/$(basename "$f").o"
done
# Third-party audio decoder.
for f in third_party/LibAtrac9/C/src/*.c; do
  "${CC[@]}" -std=c99 -O2 -g -w -c "$f" -o "$OUT/atrac9/$(basename "$f" .c).o"
done
# The runtime. vulkan_smoke needs the Vulkan loader, which iPadOS does not have.
printf 'int vulkan_smoke(void) { return 1; }\n' > "$OUT/vulkan_smoke_stub.c"
for f in src/probe.c src/runtime*.c src/platform.c "$OUT/vulkan_smoke_stub.c"; do
  "${CC[@]}" -std=c11 -O2 -g -Wall -Wextra -Wno-unknown-warning-option -Wno-unused-but-set-global -Wno-unused-parameter \
    -pthread -DBB_IOS=1 "${inc[@]}" -I"$DEPS/include" -I. -Isrc -Irecomp/src -I"$NATIVE" \
    -c "$f" -o "$OUT/rt/$(basename "$f").o"
done
mkdir -p "$ROOT/Vendor/runtime/lib"
libtool -static -o "$ROOT/Vendor/runtime/lib/libbbruntime.a" "$OUT"/cpu/*.o "$OUT"/atrac9/*.o "$OUT"/rt/*.o \
  "$DEPS/lib/libZydis.a" "$DEPS/lib/libZycore.a"

# The GPU library.
cmake -S gpu -B "$OUT/gpu" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBB_PGO=off -DBB_LTO=OFF \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_PREFIX_PATH="$DEPS" -DCMAKE_FIND_ROOT_PATH="$DEPS" -DCMAKE_INSTALL_NAME_DIR=@rpath \
  -DCMAKE_BUILD_WITH_INSTALL_NAME_DIR=ON -DVulkan_INCLUDE_DIR="$DEPS/include" \
  -DVulkan_LIBRARY="$DEPS/lib/libMoltenVK.dylib" >/dev/null
ninja -C "$OUT/gpu" bbgpu > "$OUT/gpu-build.log" 2>&1 || { tail -40 "$OUT/gpu-build.log" >&2; echo "GPU library build failed ($OUT/gpu-build.log)" >&2; exit 1; }
cp "$OUT/gpu/libbbgpu.dylib" "$ROOT/Vendor/runtime/lib/libbbgpu.dylib"
install_name_tool -id @rpath/libbbgpu.dylib "$ROOT/Vendor/runtime/lib/libbbgpu.dylib" || true
# Copy the runtime's start-up scripts and patch file into the app's script folder.
rm -rf "$ROOT/App/bbpy/runtime"; mkdir -p "$ROOT/App/bbpy/runtime/scripts" "$ROOT/App/bbpy/runtime/patches"
cp scripts/*.py "$ROOT/App/bbpy/runtime/scripts/"; cp patches/Bloodborne.xml "$ROOT/App/bbpy/runtime/patches/"
echo "Done: $ROOT/Vendor/runtime/lib"
