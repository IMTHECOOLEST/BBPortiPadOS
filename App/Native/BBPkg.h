#ifndef BB_PKG_H
#define BB_PKG_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void (*bb_pkg_progress)(uint32_t done, uint32_t total, void *user);
/* Extracts a PS4 .pkg into `out`. Returns 0 on success; otherwise a message is left in `err`. */
int bb_pkg_extract(const char *pkg, const char *out, bb_pkg_progress progress, void *user,
                   char *err, size_t errlen);
#ifdef BB_HAVE_PKGTOOL
/* Provided by the adapter around the extractor's source (Vendor/pkgtool-adapter). */
int bb_pkgtool_extract(const char *pkg, const char *out, bb_pkg_progress progress, void *user,
                       char *err, size_t errlen);
#endif
#ifdef __cplusplus
}
#endif
#endif
