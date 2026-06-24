// Cosim retire-record shared between SimX core and the DPI bridge.
// Mirror this layout in SystemVerilog (simx_pkg.sv) when wiring the monitor.

#pragma once

#include <stdint.h>

#ifndef SIMX_COSIM_MAX_THREADS
#define SIMX_COSIM_MAX_THREADS 32
#endif

#ifdef __cplusplus
namespace vortex {
extern "C" {
#endif

struct simx_retire_t {
    uint64_t uuid;
    uint32_t cid;
    uint32_t wid;
    uint64_t pc;
    uint32_t tmask;       // bit i set => thread i active
    uint8_t  wb;          // 1 if writeback present
    uint8_t  is_fp;       // 0 = integer dst, 1 = float dst
    uint8_t  rd;          // destination register index
    uint8_t  sop;
    uint8_t  eop;
    uint8_t  _pad[7];   // align result[] to 8 bytes after the 33 preceding bytes
    uint64_t result[SIMX_COSIM_MAX_THREADS];
};

#ifdef __cplusplus
} // extern "C"
} // namespace vortex
#endif
