#include "BBProbe.h"
#include <stddef.h>
#include <string.h>
#include <sys/mman.h>
#ifdef __APPLE__
#include <TargetConditionals.h>
#include <os/proc.h>
#endif

#define GIB (1ull << 30)
#define MAX_BLOCKS 1024

static void *reserve(size_t size) {
    void *p = mmap(NULL, size, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    return p == MAP_FAILED ? NULL : p;
}

void bb_probe_address_space(BBVAProbe *out) {
    memset(out, 0, sizeof *out);
    /* The largest single block first. */
    for (uint64_t size = 512 * GIB; size >= GIB; size >>= 1) {
        void *p = reserve((size_t)size);
        if (p) {
            out->largest_block = size;
            uint64_t end = (uint64_t)(uintptr_t)p + size;
            if (end > out->highest_address) out->highest_address = end;
            munmap(p, (size_t)size);
            break;
        }
    }
    /* Then as many 1 GiB blocks as the system gives. */
    static void *blocks[MAX_BLOCKS];
    int n = 0;
    while (n < MAX_BLOCKS) {
        void *p = reserve((size_t)GIB);
        if (!p) break;
        blocks[n++] = p;
        uint64_t end = (uint64_t)(uintptr_t)p + GIB;
        if (end > out->highest_address) out->highest_address = end;
    }
    out->reserved_total = (uint64_t)n * GIB;
    for (int i = 0; i < n; ++i) munmap(blocks[i], (size_t)GIB);
}

uint64_t bb_available_memory(void) {
#if defined(__APPLE__) && TARGET_OS_IPHONE
    return (uint64_t)os_proc_available_memory();
#else
    return 0;
#endif
}
