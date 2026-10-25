// Connects the app's .pkg import (BBPkg.c) to the extractor in third_party/ps4-pkg-tools
// (ExtractPkg in src/pkg_tool/lib.h). Compiled in only when scripts/ios/build_pkgtool.sh has run,
// which puts lib.h into Vendor/pkgtool/include and defines BB_HAVE_PKGTOOL (Config/Local.xcconfig).
#if __has_include("pkg_tool/lib.h")
#include <cstdio>
#include <exception>
#include <string>
#include <vector>
#include "BBPkg.h"
#include "pkg_tool/lib.h"

extern "C" int bb_pkgtool_extract(const char *pkg, const char *out, bb_pkg_progress progress, void *user,
                                  char *err, size_t errlen) {
    auto fail = [&](const std::string &message) {
        if (err && errlen) std::snprintf(err, errlen, "%s", message.c_str());
        return -1;
    };
    try {
        const auto error = ExtractPkg(pkg, out, std::vector<int>{}, [&](uint32_t done, uint32_t total) {
            if (progress) progress(done, total, user);
        });
        if (error) return fail(*error);
        return 0;
    } catch (const std::exception &e) {
        return fail(std::string("PKG extraction failed: ") + e.what());
    } catch (...) {
        return fail("PKG extraction failed.");
    }
}
#endif
