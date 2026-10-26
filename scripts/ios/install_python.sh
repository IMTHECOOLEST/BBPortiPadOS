#!/usr/bin/env bash
# Xcode build phase: copies the embedded Python's standard library into the app bundle
# (<app>/python/lib/python3.x, which RuntimeLauncher.swift passes to CPython as its home) and signs
# the extension modules in it when the build is signed. Self-contained on purpose: it does not
# depend on BeeWare's build/utils.sh, whose API changes between releases.
#
# Extension modules stay where they are (lib-dynload/*.dylib or *.so): CPython loads them with
# dlopen. They are NOT converted into frameworks (the App Store rule): that conversion leaves
# *.fwork stubs whose path CPython resolves from sys.executable, and the embedded interpreter
# (BBRuntime.c) does not set one.
set -euo pipefail

ROOT=${PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}
XC="$ROOT/Vendor/Python.xcframework"
if [[ ! -d $XC ]]; then
  echo "error: $XC is missing; run scripts/setup_deps.sh before building" >&2
  exit 1
fi

APP=${CODESIGNING_FOLDER_PATH:-${TARGET_BUILD_DIR:?}/${FULL_PRODUCT_NAME:?}}

# Which slice of the xcframework matches this build.
case "${PLATFORM_NAME:-iphoneos}" in
  iphonesimulator) SLICE_GLOB="ios-*simulator" ;;
  *)               SLICE_GLOB="ios-arm64" ;;
esac
SRC=""
for dir in "$XC"/$SLICE_GLOB; do
  if [[ -d $dir/lib ]]; then SRC="$dir/lib"; break; fi
done
if [[ -z $SRC ]]; then
  echo "error: no $SLICE_GLOB/lib folder in $XC" >&2
  ls "$XC" >&2 || true
  exit 1
fi

DEST="$APP/python/lib"
echo "Installing the Python standard library from $SRC"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$SRC/." "$DEST/"

STDLIB=""
for dir in "$DEST"/python3.*; do
  if [[ -d $dir ]]; then STDLIB="$dir"; fi
done
if [[ -z $STDLIB || ! -f $STDLIB/os.py ]]; then
  echo "error: no python3.x standard library under $DEST" >&2
  exit 1
fi
echo "Standard library: ${STDLIB#$APP/}"

# Sign the extension modules with the build's identity (same rule as embed_libs.sh: an unsigned
# build leaves them for the sideloading tool, which signs everything in the IPA).
if [[ -n ${EXPANDED_CODE_SIGN_IDENTITY:-} && ${CODE_SIGNING_ALLOWED:-YES} != NO ]]; then
  count=0
  while IFS= read -r -d '' f; do
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$f"
    count=$((count + 1))
  done < <(find "$DEST" -type f \( -name '*.dylib' -o -name '*.so' \) -print0)
  echo "Signed $count extension modules"
else
  echo "Unsigned build: extension modules left unsigned"
fi
