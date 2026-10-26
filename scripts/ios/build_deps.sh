#!/usr/bin/env bash
# macOS + Xcode: builds the libraries the runtime links against for iPadOS (arm64) into
# Vendor/ios-deps. This is scripts/macos/build-deps.sh of bloodborne-runtime, translated: the same
# packages and versions, built with the iPhoneOS SDK. Shared libraries (SDL3, FFmpeg) are embedded
# in the app as dylibs; the rest is static. Needs: brew install pkgconf glslang nasm cmake ninja
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
PREFIX=$ROOT/Vendor/ios-deps
WORK=$ROOT/Vendor/ios-deps-build
mkdir -p "$PREFIX" "$WORK/src"

for tool in pkg-config glslangValidator nasm cmake ninja xcrun; do
  command -v $tool >/dev/null || { echo "Missing $tool (brew install pkgconf glslang nasm cmake ninja)" >&2; exit 1; }
done

VULKAN_VERSION=v1.4.365
MOLTENVK_VERSION=v1.4.2
SPIRV_CROSS_VERSION=vulkan-sdk-1.4.363.0
SDL_VERSION=release-3.4.18
FMT_VERSION=12.0.0
MAGIC_ENUM_VERSION=v0.9.7
ROBIN_MAP_VERSION=v1.4.0
VMA_VERSION=v3.3.0
MINIZ_VERSION=3.1.2
XBYAK_VERSION=v7.43
ZYDIS_VERSION=v4.1.1
XXHASH_VERSION=v0.8.3
BOOST_VERSION=1.89.0
FFMPEG_VERSION=n7.1.2

MIN=17.0
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
JOBS=$(sysctl -n hw.ncpu)
cmake_ios=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN -DCMAKE_INSTALL_PREFIX="$PREFIX"
  -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_INSTALL_NAME_DIR=@rpath -DCMAKE_BUILD_WITH_INSTALL_NAME_DIR=ON
  -DBUILD_TESTING=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5)

mark() { echo "$PREFIX/.built-$1"; }
needed() { [[ ${BB_DEPS_REBUILD:-} == "$1" || ${BB_DEPS_REBUILD:-} == all || ! -f $(mark "$1") ]]; }
fetch() {
  local name=$1 url=$2 archive=$WORK/$1.archive
  rm -rf "${WORK:?}/src/$name"; mkdir -p "$WORK/src/$name"
  if [[ $url == *.git#* ]]; then
    git clone -q --depth 1 --recurse-submodules --shallow-submodules -b "${url#*#}" "${url%#*}" "$WORK/src/$name"; return
  fi
  [[ -f $archive ]] || curl -fsSL --retry 3 -o "$archive" "$url"
  tar -xf "$archive" -C "$WORK/src/$name" --strip-components 1
}
cmake_package() {
  local name=$1 url=$2; shift 2
  needed "$name" || return 0
  echo "== $name"
  fetch "$name" "$url"
  cmake -S "$WORK/src/$name" -B "$WORK/$name" "${cmake_ios[@]}" "$@" >/dev/null
  cmake --build "$WORK/$name" -j "$JOBS" >/dev/null
  cmake --install "$WORK/$name" >/dev/null
  touch "$(mark "$name")"
}
gh() { echo "https://github.com/$1/archive/refs/tags/$2.tar.gz"; }

cmake_package vulkan-headers "$(gh KhronosGroup/Vulkan-Headers $VULKAN_VERSION)"

# MoltenVK: the Khronos release's iOS library. There is no Vulkan loader on iOS: SDL3 loads this
# library (SDL_VULKAN_LIBRARY, set by the app). The release ships it for iOS as a dynamic XCFramework
# (MoltenVK.xcframework/ios-arm64/MoltenVK.framework/MoltenVK, a dylib); the naked
# dylib/iOS/libMoltenVK.dylib of older releases is macOS only now. Either one is copied out as
# libMoltenVK.dylib, the name the rest of the build and the app use.
moltenvk_ios_library() { # $1: the extracted release. Prints the device library, never a simulator's.
  find "$1" -type f \( -path '*dylib/iOS/libMoltenVK.dylib' \
    -o -path '*MoltenVK.xcframework/ios-*/MoltenVK.framework/MoltenVK' \) \
    ! -path '*simulator*' ! -path '*maccatalyst*' | sort | sed -n 1p
}
if needed moltenvk; then
  echo "== moltenvk"
  a=$WORK/moltenvk-ios.tar
  [[ -f $a ]] || curl -fsSL --retry 3 -o "$a" "https://github.com/KhronosGroup/MoltenVK/releases/download/$MOLTENVK_VERSION/MoltenVK-ios.tar"
  rm -rf "$WORK/src/moltenvk"; mkdir -p "$WORK/src/moltenvk"; tar -xf "$a" -C "$WORK/src/moltenvk"
  dylib=$(moltenvk_ios_library "$WORK/src/moltenvk")
  if [[ -z $dylib ]]; then
    echo "No iOS MoltenVK library in MoltenVK-ios.tar of $MOLTENVK_VERSION. It holds:" >&2
    find "$WORK/src/moltenvk" \( -name '*.dylib' -o -name '*.framework' -o -name '*.xcframework' -o -name '*.a' \) \
      | sed "s#^$WORK/src/moltenvk/##" | sort | sed -n 1,40p >&2
    exit 1
  fi
  echo "   ${dylib#"$WORK"/src/moltenvk/}"
  lipo -archs "$dylib" | tr ' ' '\n' | grep -qx arm64 || { echo "$dylib has no arm64 slice: $(lipo -archs "$dylib")" >&2; exit 1; }
  mkdir -p "$PREFIX/lib"; cp "$dylib" "$PREFIX/lib/libMoltenVK.dylib"
  install_name_tool -id @rpath/libMoltenVK.dylib "$PREFIX/lib/libMoltenVK.dylib"
  codesign --force --sign - "$PREFIX/lib/libMoltenVK.dylib"
  touch "$(mark moltenvk)"
fi

cmake_package spirv-cross "$(gh KhronosGroup/SPIRV-Cross $SPIRV_CROSS_VERSION)" \
  -DSPIRV_CROSS_SHARED=OFF -DSPIRV_CROSS_STATIC=ON -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF \
  -DSPIRV_CROSS_ENABLE_HLSL=OFF -DSPIRV_CROSS_ENABLE_CPP=OFF -DSPIRV_CROSS_ENABLE_REFLECT=OFF \
  -DSPIRV_CROSS_ENABLE_C_API=OFF -DSPIRV_CROSS_ENABLE_UTIL=OFF
cmake_package sdl3 "$(gh libsdl-org/SDL $SDL_VERSION)" -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
cmake_package fmt "$(gh fmtlib/fmt $FMT_VERSION)" -DFMT_TEST=OFF -DFMT_DOC=OFF
cmake_package magic-enum "$(gh Neargye/magic_enum $MAGIC_ENUM_VERSION)" \
  -DMAGIC_ENUM_OPT_BUILD_EXAMPLES=OFF -DMAGIC_ENUM_OPT_BUILD_TESTS=OFF
cmake_package xbyak "$(gh herumi/xbyak $XBYAK_VERSION)"
cmake_package robin-map "$(gh Tessil/robin-map $ROBIN_MAP_VERSION)"
cmake_package vma "$(gh GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator $VMA_VERSION)"
cmake_package miniz "$(gh richgel999/miniz $MINIZ_VERSION)" -DBUILD_EXAMPLES=OFF -DBUILD_FUZZERS=OFF -DBUILD_TESTS=OFF

if needed zydis; then
  echo "== zydis"
  fetch zydis "https://github.com/zyantific/zydis.git#$ZYDIS_VERSION"
  cmake -S "$WORK/src/zydis/dependencies/zycore" -B "$WORK/zycore" "${cmake_ios[@]}" -DBUILD_SHARED_LIBS=OFF >/dev/null
  cmake --build "$WORK/zycore" -j "$JOBS" >/dev/null && cmake --install "$WORK/zycore" >/dev/null
  # Cross-compiling for iOS, CMake searches for packages under the SDK only, not in CMAKE_PREFIX_PATH
  # (the macOS build is native and finds Zycore there). Zydis is pointed at the installed package.
  zycore_cfg=$(find "$PREFIX" \( -iname 'zycoreconfig.cmake' -o -iname 'zycore-config.cmake' \) | sed -n 1p)
  if [[ -z $zycore_cfg ]]; then
    echo "Zycore installed no CMake package file. It installed:" >&2
    find "$PREFIX" -ipath '*zycore*' | sed -n 1,30p >&2
    exit 1
  fi
  zycore_dir=$(dirname "$zycore_cfg")
  cmake -S "$WORK/src/zydis" -B "$WORK/zydis" "${cmake_ios[@]}" -DBUILD_SHARED_LIBS=OFF -DZYAN_SYSTEM_ZYCORE=ON \
    -DZycore_DIR="$zycore_dir" -Dzycore_DIR="$zycore_dir" -DCMAKE_FIND_ROOT_PATH="$PREFIX" \
    -DCMAKE_C_FLAGS="-I$PREFIX/include" -DZYDIS_BUILD_TOOLS=OFF -DZYDIS_BUILD_EXAMPLES=OFF -DZYDIS_BUILD_DOXYGEN=OFF >/dev/null
  cmake --build "$WORK/zydis" -j "$JOBS" >/dev/null && cmake --install "$WORK/zydis" >/dev/null
  touch "$(mark zydis)"
fi
if needed xxhash; then
  echo "== xxhash"
  fetch xxhash "$(gh Cyan4973/xxHash $XXHASH_VERSION)"
  cmake -S "$WORK/src/xxhash/cmake_unofficial" -B "$WORK/xxhash" "${cmake_ios[@]}" -DXXHASH_BUILD_XXHSUM=OFF -DBUILD_SHARED_LIBS=OFF >/dev/null
  cmake --build "$WORK/xxhash" -j "$JOBS" >/dev/null && cmake --install "$WORK/xxhash" >/dev/null
  touch "$(mark xxhash)"
fi
if needed boost; then
  echo "== boost"
  fetch boost "https://github.com/boostorg/boost/releases/download/boost-$BOOST_VERSION/boost-$BOOST_VERSION-cmake.tar.xz"
  cmake -S "$WORK/src/boost" -B "$WORK/boost" "${cmake_ios[@]}" \
    -DBOOST_INCLUDE_LIBRARIES='asio;container;container_hash;icl;intrusive;pool;preprocessor' \
    -DBOOST_SKIP_INSTALL_RULES=OFF -DBOOST_CONTEXT_ARCHITECTURE=arm64 -DBOOST_CONTEXT_ABI=aapcs >/dev/null
  cmake --build "$WORK/boost" -j "$JOBS" >/dev/null && cmake --install "$WORK/boost" >/dev/null
  touch "$(mark boost)"
fi
# FFmpeg: the decoders the game's movies need, shared, as in the macOS build.
if needed ffmpeg; then
  echo "== ffmpeg"
  fetch ffmpeg "$(gh FFmpeg/FFmpeg $FFMPEG_VERSION)"
  (cd "$WORK/src/ffmpeg" && ./configure --prefix="$PREFIX" --enable-cross-compile --arch=aarch64 --target-os=darwin \
    --cc="xcrun --sdk iphoneos clang -arch arm64" --cxx="xcrun --sdk iphoneos clang++ -arch arm64" \
    --extra-cflags="-miphoneos-version-min=$MIN -isysroot $SDK" \
    --extra-ldflags="-arch arm64 -miphoneos-version-min=$MIN -isysroot $SDK" \
    --enable-shared --disable-static --disable-programs --disable-doc --disable-avdevice \
    --disable-avfilter --disable-network --disable-autodetect --enable-videotoolbox \
    --install-name-dir=@rpath >/dev/null && make -j "$JOBS" >/dev/null && make install >/dev/null)
  touch "$(mark ffmpeg)"
fi
echo "iOS dependencies are in $PREFIX"
