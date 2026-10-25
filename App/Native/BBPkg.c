#include "BBPkg.h"
#include <stdio.h>

int bb_pkg_extract(const char *pkg, const char *out, bb_pkg_progress progress, void *user,
                   char *err, size_t errlen) {
#ifdef BB_HAVE_PKGTOOL
    return bb_pkgtool_extract(pkg, out, progress, user, err, errlen);
#else
    (void)pkg; (void)out; (void)progress; (void)user;
    if (err && errlen)
        snprintf(err, errlen,
                 "No PKG extractor is linked into this build. Extract the .pkg on a Mac with "
                 "ps4-pkg-tool and choose the resulting folder instead (see docs/STATUS.md).");
    return -1;
#endif
}
