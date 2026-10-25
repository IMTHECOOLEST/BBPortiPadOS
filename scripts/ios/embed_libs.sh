#!/usr/bin/env bash
# Xcode build phase: copies the dylibs the runtime needs into the app's Frameworks folder and
# signs them with the build's identity (when the build is signed). librecomp.dylib is made from
# your own game by scripts/mac/build_recomp_ios.sh; it is embedded when it exists.
set -euo pipefail
ROOT=${PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}
DEST=${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}
mkdir -p "$DEST"
copy() {
  [[ -e $1 ]] || return 0
  cp -fL "$1" "$DEST/"
  local f="$DEST/$(basename "$1")"
  if [[ -n ${EXPANDED_CODE_SIGN_IDENTITY:-} && ${CODE_SIGNING_ALLOWED:-YES} != NO ]]; then
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$f"
  fi
}
# Shared libraries are copied under the name the others load them by (libSDL3.0.dylib,
# libavcodec.61.dylib: the major-version links), not under every alias.
for lib in "$ROOT"/Vendor/ios-deps/lib/lib*.dylib; do
  name=$(basename "$lib")
  if [[ $name =~ ^lib[A-Za-z0-9]+\.[0-9]+\.dylib$ || $name == libMoltenVK.dylib ]]; then copy "$lib"; fi
done
copy "$ROOT/Vendor/runtime/lib/libbbgpu.dylib"
copy "$ROOT/Vendor/recomp/librecomp.dylib"
