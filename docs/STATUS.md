# Status

**Nothing here has been compiled or run.** This was written on Linux without Xcode, a Mac, a
device or network access. What was checked: the C files in `App/Native` pass a syntax check, the
Python, YAML and plists parse, the shell scripts pass `bash -n`, and all five runtime patches and
both recomp patches apply, in order, to the source you sent. The Swift, Objective-C, the iOS
cross-builds and the workflow have not been through a compiler or a runner.

## What the recomp repo changed

- **JIT is no longer a blocker.** bbcpu already falls back to its interpreter when `MAP_JIT`
  fails (`BB_JIT=0`), and `interp.c` calls recompiled functions. `patches/recomp/0001` makes that
  explicit on iOS (and stubs `pthread_jit_write_protect_np`). iPadOS then runs: recompiled native
  code for 240,973 of 241,821 functions, the interpreter for the rest.
- **The CPU engine exists now:** `scripts/ios/build_runtime.sh` builds bbcpu for iOS into
  `libbbruntime.a`.
- **The recompiled library is per player.** It is made from your `eboot.bin`
  (`scripts/mac/build_recomp_ios.sh`, using `patches/recomp/0002` so the same generator compiles
  for the iPhoneOS SDK), is about 400 MB and must never be published. The workflow cannot build it.

## Still open

1. **Speed.** The recompiled code costs the same CPU as the translator (the recomp docs measure
   420% of one core on a Mac). An M1 iPad Pro has four performance cores. The 130 `setjmp` callers,
   660 import stubs and every function a patch changes (resolution and frame-rate patches add some)
   run in the interpreter. Whether 540p reaches a playable rate is unknown.
2. **Address space.** `patches/runtime/0002` moves the guest ranges to 16 GiB (game mappings,
   0x400000000-0x800000000) and 8 GiB (host memory the guest sees, 0x800000000-0xa00000000), under
   the ~64 GiB macos-on-ios-public reports. These are starting values, not measurements. Use
   *Advanced > Probe address space* on the iPad, then rebuild with `-DBB_USER_MIN=...`. The runtime
   also reserves them before `main` (`platform.c`, a constructor), and the macOS build notes that
   the GPU driver reserves about 24 GiB there; whether iPadOS does the same is unknown.
3. **Memory.** The game's 5 GiB of direct memory is a shared mapping; on iOS it is an unlinked file
   in the app's temp folder (shm_open is denied in the sandbox), so under pressure it pages to
   flash instead of killing the app (which may be slow). On the 8 GB M1 iPad Pro the entitlement
   gives roughly 5-6 GB, which is tight next to the guest's 5 GiB. A 12 GB or 16 GB M5 iPad Pro
   should make memory a smaller worry (Advanced shows the exact limit the device gives; nothing
   here is tuned to a particular amount), leaving speed (point 1) and the address layout
   (point 2) as the main risks. macos-on-ios-public reports a Mac game running on an iPad Pro 13"
   M5, with the same entitlements.
4. **Cross-builds.** `scripts/ios/build_deps.sh` and `build_runtime.sh` translate the runtime's own
   macOS scripts. Likely trouble spots: FindVulkan without a loader (the script passes MoltenVK as
   `Vulkan_LIBRARY`), pkg-config for the shared FFmpeg, the Metal backend's Objective-C++ on iOS,
   `-undefined dynamic_lookup` in the GPU library (its `runtime_*` symbols must come from the app;
   the app links with `-export_dynamic`), and MoltenVK's release layout.
5. **Window.** The runtime runs the game on a thread and pumps SDL events on the main thread, as
   on macOS; the app calls it on the main thread. Whether SDL3's iOS backend creates its window
   correctly beside the SwiftUI app lifecycle has to be tried on a device.
6. **.pkg import.** The ps4-pkg-tools source you sent is vendored in `third_party/ps4-pkg-tools`.
   `scripts/ios/build_pkgtool.sh` builds its core (`ExtractPkg`) with cryptopp and zlib for iPadOS
   (the C++ standard it asks for is C++23; Xcode 16's clang accepts it), and
   `App/Native/BBPkgAdapter.cpp` connects it to the import screen. Unbuilt and untested: whether
   cryptopp builds for iOS cleanly, and how long and how much disk a 40 GB extraction takes on the
   iPad (the game needs about its size again in free space; picking an already extracted folder
   needs none). The macOS binaries you sent are not used by the app.
7. **Python.** `bb_pipeline.py` follows `run.sh`; BeeWare's release asset names and its
   `install_python` build phase are written from memory. `mods.py` is not run (no mods).
8. **Signing.** The app and every dylib in Frameworks must be signed by the same team; the
   embed script signs them in an Xcode build, and a sideloading tool does it for an IPA.

## Gamepad notes

The touchpad cannot tell a finger in the exact centre from no finger (GameController reports
0,0 for both). Gyro axis signs are unchecked on a controller. Haptics use CoreHaptics on the
controller's two handles.

## Not done

Mods, patches, profiles and saves tabs; 4:3 and other aspect ratios; MetalFX or other upscalers;
online play; any profiling. Optimisation is limited to documented, memory-conservative defaults
(`BB_PREUPLOAD=0`, `live_resolution=0`, 30 FPS cap).
