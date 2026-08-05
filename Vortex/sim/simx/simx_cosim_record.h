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
    uint8_t  fu_type;    // FUType: 0=ALU 1=LSU 2=FPU 3=SFU ... (load-data not observable at DUT commit probe)
    uint8_t  is_volatile;// 1 = read a perf-counter CSR (mcycle/minstret/...) → exclude from lockstep compare
    uint8_t  is_fsqrt;   // 1 = FPU FSQRT op (OBS-014): DUT hardware fsqrt.s is 1 ULP off the
                         // IEEE-correct SoftFloat result. Lets the lockstep comparator apply a
                         // DOCUMENTED, bounded 1-ULP tolerance to sqrt writebacks ONLY — every
                         // other FP op (+,-,*,/,fma,cvt) stays bit-exact. See docs/RTL_OBSERVATIONS.md.
    uint8_t  _pad[4];    // align result[] to 8 bytes after the 36 preceding bytes
    uint64_t result[SIMX_COSIM_MAX_THREADS];
    uint64_t mem_addr[SIMX_COSIM_MAX_THREADS]; // LSU only: per-thread effective load
                          // address (0 for non-loads). Lets the lockstep SB apply the
                          // same region filter as the end-state check to load lanes
                          // (skip out-of-[RAM_BASE,DATA_LIMIT)/uninitialised loads).
};

#ifdef __cplusplus
} // extern "C"
} // namespace vortex
#endif
