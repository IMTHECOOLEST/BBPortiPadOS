#!/usr/bin/env bash
# Fetches what the app needs into Vendor/ (run by CI, or on a Mac before `xcodegen generate`):
#   - BeeWare's Python-Apple-support (embedded CPython that runs the runtime's prepare scripts)
#   - the runtime's Python scripts and patch file, copied into App/bbpy/runtime/
# The runtime libraries come from scripts/ios/build_deps.sh and scripts/ios/build_runtime.sh
# (Vendor/runtime/lib/libbbruntime.a, libbbgpu.dylib); an extractor library from you, if you built
# one (Vendor/pkgtool/lib/libpkgtool.a).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
mkdir -p Vendor

# ---- Python (iOS) ----
if [[ ! -d Vendor/Python.xcframework ]]; then
  mkdir -p Vendor/py-dl && cd Vendor/py-dl
  if [[ -n ${PYTHON_SUPPORT_URL:-} ]]; then
    curl -fsSL -o support.tar.gz "$PYTHON_SUPPORT_URL"
  else
    PYV=${PYTHON_VERSION:-3.13}
    TAG=$(gh release list --repo beeware/Python-Apple-support --limit 60 --json tagName -q '.[].tagName' | grep "^${PYV}-" | head -1)
    [[ -n $TAG ]] || { echo "No Python-Apple-support release found for $PYV" >&2; exit 1; }
    gh release download "$TAG" --repo beeware/Python-Apple-support --pattern "Python-${PYV}-iOS-support.*.tar.gz" --output support.tar.gz --clobber
  fi
  tar -xzf support.tar.gz
  cd "$ROOT"
  mv Vendor/py-dl/Python.xcframework Vendor/Python.xcframework
  rm -rf Vendor/py-dl
fi

# ---- the runtime's prepare scripts ----
RUNTIME_SRC=${RUNTIME_DIR:-}
if [[ -z $RUNTIME_SRC ]]; then
  # build_runtime.sh has usually cloned it already: use that copy (re-cloning would also delete its
  # build logs).
  if [[ ! -d Vendor/runtime-src/scripts || ! -f Vendor/runtime-src/patches/Bloodborne.xml ]]; then
    RUNTIME_REPO=${RUNTIME_REPO:-https://github.com/bloodborne-native/bloodborne-runtime.git}
    rm -rf Vendor/runtime-src
    git clone --depth 1 "$RUNTIME_REPO" Vendor/runtime-src
  fi
  RUNTIME_SRC=$ROOT/Vendor/runtime-src
fi
rm -rf App/bbpy/runtime
mkdir -p App/bbpy/runtime/scripts App/bbpy/runtime/patches
cp "$RUNTIME_SRC"/scripts/*.py App/bbpy/runtime/scripts/
cp "$RUNTIME_SRC"/patches/Bloodborne.xml App/bbpy/runtime/patches/

# ---- optional libraries -> Config/Local.xcconfig ----
LOCAL=Config/Local.xcconfig
: > "$LOCAL"
if [[ -f Vendor/runtime/lib/libbbruntime.a ]]; then
  echo "BB_RUNTIME_LDFLAGS = -force_load \$(SRCROOT)/Vendor/runtime/lib/libbbruntime.a -lbbgpu -lc++ -lz" >> "$LOCAL"
fi
if [[ -f Vendor/pkgtool/lib/libpkgtool.a ]]; then
  echo "BB_PKGTOOL_LDFLAGS = -force_load \$(SRCROOT)/Vendor/pkgtool/lib/libpkgtool.a -lc++" >> "$LOCAL"
  echo "BB_EXTRA_DEFINES = BB_HAVE_PKGTOOL=1" >> "$LOCAL"
fi
echo "Dependencies ready."
