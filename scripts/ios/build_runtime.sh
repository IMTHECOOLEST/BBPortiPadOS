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
# This repo's changes to the runtime and to bbcpu, each applied once. A patch that neither applies
# nor is already applied stops the build here (the upstream source has moved on): skipping it
# silently only moves the failure to a link error much later.
apply_patches() { # $1: label, then the patch files
  local label=$1 p; shift
  for p in "$@"; do
    if patch -p1 --dry-run -s < "$p" >/dev/null 2>&1; then
      patch -p1 -s < "$p"; echo "patched$label: $(basename "$p")"
    elif patch -R -p1 --dry-run -s < "$p" >/dev/null 2>&1; then
      echo "already applied$label: $(basename "$p")"
    else
      echo "PATCH DOES NOT APPLY$label: $(basename "$p") (the upstream source changed; update the patch)" >&2
      return 1
    fi
  done
}
apply_patches "" "$ROOT"/patches/runtime/*.patch
( cd recomp && apply_patches " (recomp)" "$ROOT"/patches/recomp/*.patch )

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CC=(xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -isysroot "$SDK")
OUT=$SRC/out-ios
rm -rf "$OUT"; mkdir -p "$OUT/cpu" "$OUT/atrac9" "$OUT/rt"
export PKG_CONFIG_LIBDIR=$DEPS/lib/pkgconfig:$DEPS/share/pkgconfig
read -r -a inc <<< "$(pkg-config --cflags sdl3)"
[[ ${#inc[@]} -gt 0 ]] || { echo "pkg-config found no SDL3 flags in $DEPS" >&2; exit 1; }
NATIVE=$ROOT/App/Native

# A file that does not compile does not stop the others: one run shows every error.
failed=0
# bbcpu (the recompiled code's runtime and the interpreter; the translator stays off on iPadOS).
for f in recomp/src/cpu/*.c; do
  "${CC[@]}" -std=gnu11 -O2 -g -Wall -Wextra -Wno-unused-parameter -I"$DEPS/include" -c "$f" -o "$OUT/cpu/$(basename "$f").o" || failed=1
done
# The assembly file: no -std (it is not C), and the C compiler's warning flags do not apply.
"${CC[@]}" -O2 -g -I"$DEPS/include" -Irecomp/src/cpu -c recomp/src/cpu/hostcall.S -o "$OUT/cpu/hostcall.S.o" || failed=1
# Third-party audio decoder.
for f in third_party/LibAtrac9/C/src/*.c; do
  "${CC[@]}" -std=c99 -O2 -g -w -c "$f" -o "$OUT/atrac9/$(basename "$f" .c).o" || failed=1
done
# The runtime. vulkan_smoke needs the Vulkan loader, which iPadOS does not have.
printf 'int vulkan_smoke(void) { return 1; }\n' > "$OUT/vulkan_smoke_stub.c"
for f in src/probe.c src/runtime*.c src/platform.c "$OUT/vulkan_smoke_stub.c"; do
  "${CC[@]}" -std=c11 -O2 -g -Wall -Wextra -Wno-unknown-warning-option -Wno-unused-but-set-global -Wno-unused-parameter \
    -pthread -DBB_IOS=1 ${inc[@]+"${inc[@]}"} -I"$DEPS/include" -I. -Isrc -Irecomp/src -I"$NATIVE" \
    -c "$f" -o "$OUT/rt/$(basename "$f").o" || failed=1
done
mkdir -p "$ROOT/Vendor/runtime/lib"
[[ $failed == 0 ]] || { echo "Some files above did not compile." >&2; exit 1; }
libtool -static -o "$ROOT/Vendor/runtime/lib/libbbruntime.a" "$OUT"/cpu/*.o "$OUT"/atrac9/*.o "$OUT"/rt/*.o \
  "$DEPS/lib/libZydis.a" "$DEPS/lib/libZycore.a"

# The GPU library.
# Xcode's libc++ keeps std::jthread and std::stop_token (the shadPS4 video core uses both) behind
# -fexperimental-library; without it: "no type named 'stop_token' in namespace 'std'". The flag
# is added to the bbgpu target itself, so it applies whatever the CMake file sets for itself, and
# only at compile time (jthread is header-only, so nothing extra is linked).
if ! grep -q 'bb-ios-experimental-library' gpu/CMakeLists.txt; then
  cat >> gpu/CMakeLists.txt <<'CMAKE_EOF'

# bb-ios-experimental-library (added by scripts/ios/build_runtime.sh)
if(APPLE AND TARGET bbgpu)
  target_compile_options(bbgpu PRIVATE "$<$<COMPILE_LANGUAGE:CXX,OBJCXX>:-fexperimental-library>")
endif()
CMAKE_EOF
fi
LOGS=$ROOT/Vendor/logs; mkdir -p "$LOGS"
cmake -S gpu -B "$OUT/gpu" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBB_PGO=off -DBB_LTO=OFF \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_PREFIX_PATH="$DEPS" -DCMAKE_FIND_ROOT_PATH="$DEPS" -DCMAKE_INSTALL_NAME_DIR=@rpath \
  -DCMAKE_BUILD_WITH_INSTALL_NAME_DIR=ON -DVulkan_INCLUDE_DIR="$DEPS/include" \
  -DVulkan_LIBRARY="$DEPS/lib/libMoltenVK.dylib" > "$LOGS/gpu-configure.log" 2>&1 \
  || { tail -40 "$LOGS/gpu-configure.log" >&2; echo "GPU library configure failed (Vendor/logs/gpu-configure.log)" >&2; exit 1; }
# -k 0: keep going after the first failure, so one run lists every error (the tail of the log
# alone shows only the last of them).
if ! ninja -C "$OUT/gpu" -k 0 bbgpu > "$OUT/gpu-build.log" 2>&1; then
  cp "$OUT/gpu-build.log" "$LOGS/gpu-build.log"
  echo "---- first errors ----" >&2
  grep -n -m 60 -E 'error:|fatal error:|undefined symbol|ld: ' "$OUT/gpu-build.log" >&2 || true
  echo "---- end of the log ----" >&2
  tail -15 "$OUT/gpu-build.log" >&2
  echo "GPU library build failed (the whole log is in Vendor/logs/gpu-build.log)" >&2
  exit 1
fi
cp "$OUT/gpu/libbbgpu.dylib" "$ROOT/Vendor/runtime/lib/libbbgpu.dylib"
install_name_tool -id @rpath/libbbgpu.dylib "$ROOT/Vendor/runtime/lib/libbbgpu.dylib" || true
# Copy the runtime's start-up scripts and patch file into the app's script folder.
rm -rf "$ROOT/App/bbpy/runtime"; mkdir -p "$ROOT/App/bbpy/runtime/scripts" "$ROOT/App/bbpy/runtime/patches"
cp scripts/*.py "$ROOT/App/bbpy/runtime/scripts/"; cp patches/Bloodborne.xml "$ROOT/App/bbpy/runtime/patches/"
echo "Done: $ROOT/Vendor/runtime/lib"
