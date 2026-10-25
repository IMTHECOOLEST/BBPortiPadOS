#ifndef BB_PROBE_H
#define BB_PROBE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
    uint64_t reserved_total;   /* bytes reservable in 1 GiB blocks (up to 1 TiB tried) */
    uint64_t largest_block;    /* largest single PROT_NONE reservation that succeeded */
    uint64_t highest_address;  /* highest end address among the blocks */
} BBVAProbe;
/* Reserves address space (PROT_NONE, nothing is committed) and releases it again. */
void bb_probe_address_space(BBVAProbe *out);
/* os_proc_available_memory(): what the app may still allocate; 0 when unknown. */
uint64_t bb_available_memory(void);
#ifdef __cplusplus
}
#endif
#endif
