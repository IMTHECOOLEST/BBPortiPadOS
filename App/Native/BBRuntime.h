#ifndef BB_RUNTIME_H
#define BB_RUNTIME_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
/* 1 when the game runtime (bb_probe_main) is linked into the app. */
int bb_runtime_available(void);
/* Step 1, on any thread: starts the embedded Python, runs the runtime's prepare scripts on the
 * game folder, and keeps the runtime's arguments. The runtime's output goes to log_path.
 * 0 on success; otherwise `err` has a message. */
int bb_runtime_prepare(const char *python_home, const char *stdlib, const char *scripts_dir,
                       const char *game_dir, const char *data_dir, const char *fps,
                       const char *log_path, char *err, size_t errlen);
/* Step 2, on the MAIN thread: runs the runtime. The game runs on a thread of its own while the
 * main thread pumps the window's events (as on macOS). Returns when the game exits. */
int bb_runtime_run(char *err, size_t errlen);
#ifdef __cplusplus
}
#endif
#endif
