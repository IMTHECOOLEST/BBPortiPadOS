# ps4-pkg-tools (vendored)

The PS4 .pkg extraction code used by the app's .pkg import, from the ps4-pkg-tools source you
supplied (itself shadPS4's PKG code, GPL-2.0-or-later; licence files are kept here). Only `src/`
and the CMake file are included; the GUI is left out and the external libraries (cryptopp,
cryptopp-cmake, zlib) are fetched by `scripts/ios/build_pkgtool.sh`, from the repositories its
`.gitmodules` names. The app links the `ps4_pkg_tool_core` library through
`App/Native/BBPkgAdapter.cpp`; the original README is `README.upstream.md`.
