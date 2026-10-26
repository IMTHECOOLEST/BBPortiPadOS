#!/usr/bin/env bash
# Xcode build phase: copies the embedded Python's standard library into the app bundle
# (<app>/python/lib/python3.x, which RuntimeLauncher.swift passes to CPython as its home) and signs
# the extension modules in it when the build is signed. Self-contained on purpose: it does not
# depend on BeeWare's build/utils.sh, whose API changes between releases, and it FINDS the
# standard library inside Vendor/Python.xcframework instead of assuming where a given
# Python-Apple-support release puts it.
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

case "${PLATFORM_NAME:-iphoneos}" in
  iphonesimulator) SLICE_PATTERN='*simulator*' ;;
  *)               SLICE_PATTERN='*/ios-arm64/*' ;;
esac

# pick_first PATTERN LIST: the first line of LIST that matches PATTERN (empty when none does).
pick_first() {
  local pattern=$1 line
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    case $line in
      $pattern) printf '%s\n' "$line"; return 0 ;;
    esac
  done <<< "$2"
  return 0
}

# The standard library is the python3.x folder that holds os.py (find -L: it may be a symlink).
OS_FILES=$(find -L "$XC" -maxdepth 7 -type f -path '*/python3.*/os.py' 2>/dev/null | sort || true)
STDLIB_LIST=""
while IFS= read -r f; do
  [[ -n $f ]] || continue
  STDLIB_LIST+="$(dirname "$f")"$'\n'
done <<< "$OS_FILES"

STDLIB_SRC=$(pick_first "$SLICE_PATTERN" "$STDLIB_LIST")
if [[ -z $STDLIB_SRC ]]; then
  STDLIB_SRC=$(printf '%s' "$STDLIB_LIST" | head -n 1)   # shared by all slices
fi
if [[ -z $STDLIB_SRC ]]; then
  echo "error: no python3.x standard library (a folder with os.py) found in $XC" >&2
  echo "Contents of the xcframework:" >&2
  find -L "$XC" -maxdepth 4 2>/dev/null | head -n 120 >&2 || true
  exit 1
fi

NAME=$(basename "$STDLIB_SRC")
DEST="$APP/python/lib"
STDLIB="$DEST/$NAME"
echo "Installing the Python standard library from ${STDLIB_SRC#$ROOT/}"
rm -rf "$APP/python"
mkdir -p "$STDLIB"
if ! cp -RL "$STDLIB_SRC/." "$STDLIB/"; then
  rm -rf "$STDLIB"; mkdir -p "$STDLIB"
  cp -R "$STDLIB_SRC/." "$STDLIB/"
fi

# Some releases keep the compiled extension modules apart from the shared pure-Python library.
if [[ ! -d $STDLIB/lib-dynload ]]; then
  DYN_LIST=$(find -L "$XC" -maxdepth 7 -type d -name lib-dynload 2>/dev/null | sort || true)
  DYN_SRC=$(pick_first "$SLICE_PATTERN" "$DYN_LIST")
  if [[ -z $DYN_SRC ]]; then DYN_SRC=$(printf '%s' "$DYN_LIST" | head -n 1); fi
  if [[ -n $DYN_SRC ]]; then
    echo "Installing the extension modules from ${DYN_SRC#$ROOT/}"
    mkdir -p "$STDLIB/lib-dynload"
    cp -RL "$DYN_SRC/." "$STDLIB/lib-dynload/"
  else
    echo "warning: no lib-dynload folder found: Python extension modules (math, _struct, ...) will be missing" >&2
  fi
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
