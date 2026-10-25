# Bloodborne for iPadOS (work in progress)

An iPadOS app around the [bloodborne-native](https://github.com/bloodborne-native) runtime and
recompiler, aimed at an iPad Pro M1 (8 GB). You supply your own legally dumped **EU Game of the
Year (CUSA03173)** files and the **1.09 update**; nothing from the game is in this repo, and the
recompiled game library is made on your own Mac from your own copy.

**Read [docs/STATUS.md](docs/STATUS.md) first.** Nothing here has been compiled or run on a Mac or
an iPad yet.

## How the pieces fit

iPadOS cannot create executable memory at run time, so bbcpu's translator (the JIT) stays off.
Instead the game's own code runs as **ahead-of-time recompiled native code** (`librecomp.dylib`,
from bloodborne-recomp: 99.6% of the game's functions), and the few functions it does not cover
(import stubs, `setjmp` callers, patched functions) run in bbcpu's interpreter.

| Part | Where it comes from |
|---|---|
| App (SwiftUI launcher: Home, Graphics, Controls, Advanced, Log) | this repo, built by the GitHub workflow |
| Runtime (`libbbruntime.a`, `libbbgpu.dylib`, SDL3, MoltenVK, FFmpeg) | bloodborne-runtime + patches in `patches/runtime/`, built by `scripts/ios/` (also in the workflow) |
| bbcpu without the JIT | bloodborne-recomp + patches in `patches/recomp/` |
| PKG extraction | ps4-pkg-tools core, vendored, built by `scripts/ios/build_pkgtool.sh` |
| Game preparation (`run.sh`'s steps) | the runtime's Python scripts, run inside the app on embedded CPython (`App/bbpy/bb_pipeline.py`) |
| `librecomp.dylib` | **you**, on a Mac, from your game: `scripts/mac/build_recomp_ios.sh` |

## What the app does

- **Resolution:** Performance 540p (960x540), Balanced 720p (1280x720), Quality 1080p (slow); written as `output_res` in `bbport.ini`.
- **Renderer:** Metal or MoltenVK (`BB_METAL_FRAME`), as in the Mac launcher.
- **Import:** folder or `.pkg` picker for the game and the update, checked for CUSA03173 and version 01.09, merged with symlinks (nothing is copied for folders). `.pkg` files are extracted in the app with the vendored ps4-pkg-tools code (`third_party/ps4-pkg-tools`).
- **Controllers:** SDL3 for buttons, sticks and triggers; DualSense touchpad, motion, CoreHaptics rumble and optional gyro aiming through GameController (`App/Native/bb_ios_pad.m`).
- **macOS shims converted for iOS** (`patches/runtime/0004`): `mach_vm_*` to `vm_*`, `shm_open` to an unlinked temp file, `exec` restart removed, guest address layout moved under iPadOS's ~64 GiB (`0002`).
- **Memory:** `increased-memory-limit` and `extended-virtual-addressing` entitlements, and a probe in Advanced that reports what the iPad really gives.

## Steps

1. **Game folder** (needed on the Mac for step 3; optional for the app, which can extract the
   `.pkg` files itself): `scripts/mac/prepare_game_folder.sh PKG_TOOL BASE.pkg UPDATE.pkg OUT_DIR`
   makes `OUT_DIR/merged`, with the `ps4-pkg-tool` you built.
2. **The app:** push this folder to GitHub and run **Build iPad app** (about 1-3 hours the first
   time; it builds the libraries and the runtime). Or on a Mac:
   `scripts/ios/build_deps.sh && scripts/ios/build_runtime.sh && scripts/setup_deps.sh && xcodegen generate`, then Xcode.
3. **Your game library**, on a Mac (10-20 minutes, about 400 MB):
   `scripts/mac/build_recomp_ios.sh /path/to/merged` → `Vendor/recomp/librecomp.dylib`
   (never upload or commit it).
4. **Put it in the app:** `scripts/mac/embed_recomp.sh Bloodborne.ipa Vendor/recomp/librecomp.dylib`
   (or build in Xcode with the file in place: the build embeds it), then sign and install with
   your own tool and a profile that has the memory entitlements.
5. In the app: **Home** → choose the game (and update), set **Graphics**, press **Play**.

Signing: without secrets the workflow gives an unsigned IPA. For a signed one add the secrets
`BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `PROVISIONING_PROFILE_BASE64`, `KEYCHAIN_PASSWORD`.
The memory entitlements only apply if your provisioning profile includes them (paid developer
account). Variables `RUNTIME_REPO` and `RECOMP_REPO` point at other forks.

## Credits

bloodborne-native runtime, recompiler and launcher (GPL-2.0-or-later; the patches here are
changes to them), shadPS4 and ps4-pkg-tools (GPL-2.0-or-later, `third_party/ps4-pkg-tools`), BeeWare Python-Apple-support, SDL, MoltenVK, FFmpeg,
zorrobyte/macos-on-ios-public (notes on iOS address space and shims). Bloodborne is a trademark of
Sony Interactive Entertainment; this project contains no game data and is not affiliated with it.
