////////////////////////////////////////////////////////////////////////////////
// axi_traffic.cpp — AXI Memory Interface Verification Kernel
//
// Exercises AXI-specific memory traffic patterns. Run with +USE_AXI_WRAPPER
// (selects the Vortex_axi RTL top) so every memory operation is issued as an
// AXI4 transaction via the AXI wrapper instead of the native custom-mem port.
//
// Each sub-test is designed to stress a distinct aspect of the AXI wrapper:
//
//   1. Multi-line sequential R/W  — writes then reads 4 cache lines via
//                                   4 threads in parallel; exercises multiple
//                                   sequential AW/W and AR/R transactions and
//                                   the B-channel response pipeline.
//   2. Byte-granularity writes    — 4 threads write individual bytes across
//                                   a 64-byte (one cache line) buffer;
//                                   exercises non-trivial wstrb patterns in
//                                   the AXI W channel.
//   3. Write-then-read ordering   — per-thread store immediately followed by
//                                   load to same slot; exercises correct AXI
//                                   write-response (B) before read (AR/R)
//                                   ordering through the wrapper.
//   4. Dense back-to-back writes  — thread 0 sequentially writes 4 cache
//                                   lines, all threads read back in parallel;
//                                   exercises the AW/W pipeline depth and
//                                   B-channel ID matching.
//
// Configuration used for AXI wrapper:
//   DATA_WIDTH = 512 bits (64 bytes) = one cache line per AXI beat
//   ADDR_WIDTH = 32 bits
//   ID_WIDTH   = 8 bits (for 1 cluster / 1 core config)
//   AXI_NUM_BANKS = 1 (single AXI port)
//
// Result sentinel at RESULT_ADDR (0x80010000): 0x900DCAFE on success, else
// the literal error count. The UVM Gate-2 check reads this word.
////////////////////////////////////////////////////////////////////////////////

#include <stdio.h>
#include <algorithm>
#include <VX_config.h>
#include <vx_intrinsics.h>
#include <vx_print.h>
#include <vx_spawn.h>

#define PRINTF      vx_printf
#define RESULT_ADDR 0x80010000

static int make_full_tmask(int n) { return (1 << n) - 1; }

// Cache-line geometry for this config: 64 bytes = 16 ints per line.
#define LINE_INTS  16
#define NUM_LINES   4

////////////////////////////////////////////////////////////////////////////////
// Test 1: Multi-Line Sequential Read/Write
//
// Thread 0 fills 4 cache lines (64 ints) with a known pattern, forcing
// 4 AXI write transactions (AW+W+B per line). All 4 threads then read back
// in parallel with stride-4 interleaving, generating 4 AXI read transactions
// (AR+R per line) in flight simultaneously. Exercises the AR/R pipeline and
// confirms every written word is readable after the B-channel response.
//
// Expected: t1_buf[i] = 0xA000 | i  for i in 0..63
////////////////////////////////////////////////////////////////////////////////

int   t1_buf[NUM_LINES * LINE_INTS];
int   t1_errors[4];

void __attribute__((noinline)) do_t1_verify() {
    int tid = vx_thread_id();
    int local_err = 0;
    for (int i = tid; i < NUM_LINES * LINE_INTS; i += 4) {
        if (t1_buf[i] != (0xA000 | i)) local_err++;
    }
    t1_errors[tid] = local_err;
}

int test_multiline_rw() {
    PRINTF("=== T1: Multi-Line Sequential R/W ===\n");
    // Thread 0: fill 4 cache lines (4 AXI W transactions)
    vx_tmc(1);
    for (int i = 0; i < NUM_LINES * LINE_INTS; i++)
        t1_buf[i] = 0xA000 | i;
    vx_tmc_one();
    // All 4 threads: parallel strided read-verify (concurrent AR/R)
    int nt = std::min(vx_num_threads(), 4);
    for (int t = 0; t < nt; t++) t1_errors[t] = 0;
    vx_tmc(make_full_tmask(nt));
    do_t1_verify();
    vx_tmc_one();
    int total = 0;
    for (int t = 0; t < nt; t++) total += t1_errors[t];
    if (total) PRINTF("  FAIL (%d mismatches across %d threads)\n", total, nt);
    else       PRINTF("  PASS (%d cache lines, %d threads parallel read)\n", NUM_LINES, nt);
    return total;
}

////////////////////////////////////////////////////////////////////////////////
// Test 2: Byte-Granularity Writes (AXI wstrb coverage)
//
// A 64-byte (one cache line) char buffer is zeroed, then 4 threads each
// write 16 consecutive bytes at their own offset within the buffer using
// char* stores. Each 16-byte chunk fits sub-word within a 32-bit word,
// generating AXI W beats with non-trivial wstrb. Any byte-enable routing
// bug in the AXI wrapper corrupts adjacent bytes or silently drops writes.
//
// Expected: t2_buf[t*16 + j] = (char)(0xB0 + t*16 + j) for t in 0..3, j in 0..15
////////////////////////////////////////////////////////////////////////////////

char t2_buf[64];

void __attribute__((noinline)) do_t2_byte_write() {
    int tid  = vx_thread_id();
    int base = tid * 16;
    for (int j = 0; j < 16; j++)
        t2_buf[base + j] = (char)(0xB0 + base + j);
}

int test_byte_writes() {
    PRINTF("=== T2: Byte-Granularity Writes (wstrb) ===\n");
    int nt = std::min(vx_num_threads(), 4);
    // Zero the buffer (thread 0 only)
    vx_tmc(1);
    for (int i = 0; i < 64; i++) t2_buf[i] = 0;
    vx_tmc_one();
    // All threads write their byte slots
    vx_tmc(make_full_tmask(nt));
    do_t2_byte_write();
    vx_tmc_one();
    int errors = 0;
    for (int t = 0; t < nt; t++) {
        int base = t * 16;
        for (int j = 0; j < 16; j++) {
            char expected = (char)(0xB0 + base + j);
            if (t2_buf[base + j] != expected) {
                PRINTF("  FAIL t2_buf[%d]=0x%x expected 0x%x\n",
                       base + j,
                       (int)(unsigned char)t2_buf[base + j],
                       (int)(unsigned char)expected);
                errors++;
            }
        }
    }
    if (!errors) PRINTF("  PASS (%d threads, %d bytes each, 1 cache line)\n", nt, 16);
    return errors;
}

////////////////////////////////////////////////////////////////////////////////
// Test 3: Write-Then-Read Ordering (AXI W → AR/R)
//
// Each thread stores a sentinel to its slot then immediately loads from the
// same address. The AXI wrapper must ensure the B-channel write response
// precedes any AR request that could see the old (pre-write) cache contents.
// The readback result is written to t3_confirm[] for scoreboard visibility.
//
// Expected: t3_confirm[t] = 0xCC + t (means readback matched 0xC0+t)
////////////////////////////////////////////////////////////////////////////////

int t3_confirm[4];

void __attribute__((noinline)) do_t3_wr_order() {
    int tid = vx_thread_id();
    volatile int slot;
    slot = 0xC0 + tid;                 // AXI write
    int rb = slot;                     // AXI read immediately after
    t3_confirm[tid] = (rb == (0xC0 + tid)) ? (0xCC + tid) : (0xBAD00000 + tid);
}

int test_write_read_order() {
    PRINTF("=== T3: Write-Then-Read Ordering (W→AR/R) ===\n");
    int nt = std::min(vx_num_threads(), 4);
    vx_tmc(make_full_tmask(nt));
    do_t3_wr_order();
    vx_tmc_one();
    int errors = 0;
    for (int t = 0; t < nt; t++) {
        if (t3_confirm[t] != (0xCC + t)) {
            PRINTF("  FAIL t3_confirm[%d]=0x%x expected 0x%x\n",
                   t, t3_confirm[t], 0xCC + t);
            errors++;
        }
    }
    if (!errors) PRINTF("  PASS (%d threads W→R confirmed)\n", nt);
    return errors;
}

////////////////////////////////////////////////////////////////////////////////
// Test 4: Dense Back-to-Back Writes (AW/W/B pipeline)
//
// Thread 0 writes 4 cache lines sequentially in a tight loop, issuing 4
// AXI write transactions back-to-back. This stresses the AW/W pipeline
// depth and B-channel ID-to-transaction matching in the AXI wrapper.
// All 4 threads then read back in parallel to verify all lines were written
// and all B responses correctly confirmed.
//
// Expected: t4_lines[l][i] = 0xD000 | (l<<4) | i  for l in 0..3, i in 0..15
////////////////////////////////////////////////////////////////////////////////

int t4_lines[NUM_LINES][LINE_INTS];
int t4_rd_errors[4];

void __attribute__((noinline)) do_t4_verify() {
    int tid = vx_thread_id();
    int local_err = 0;
    for (int l = 0; l < NUM_LINES; l++) {
        for (int i = tid; i < LINE_INTS; i += 4) {
            int expected = 0xD000 | (l << 4) | i;
            if (t4_lines[l][i] != expected) local_err++;
        }
    }
    t4_rd_errors[tid] = local_err;
}

int test_dense_writes() {
    PRINTF("=== T4: Dense Back-to-Back Writes (AW/W/B pipeline) ===\n");
    // Thread 0: write all 4 lines (4 back-to-back AXI W transactions)
    vx_tmc(1);
    for (int l = 0; l < NUM_LINES; l++)
        for (int i = 0; i < LINE_INTS; i++)
            t4_lines[l][i] = 0xD000 | (l << 4) | i;
    vx_tmc_one();
    // All 4 threads: parallel read-back verify
    int nt = std::min(vx_num_threads(), 4);
    for (int t = 0; t < nt; t++) t4_rd_errors[t] = 0;
    vx_tmc(make_full_tmask(nt));
    do_t4_verify();
    vx_tmc_one();
    int total = 0;
    for (int t = 0; t < nt; t++) total += t4_rd_errors[t];
    if (total) PRINTF("  FAIL (%d mismatches)\n", total);
    else       PRINTF("  PASS (%d cache lines back-to-back)\n", NUM_LINES);
    return total;
}

////////////////////////////////////////////////////////////////////////////////
// main
////////////////////////////////////////////////////////////////////////////////

int main() {
    int errors = 0;

    errors += test_multiline_rw();
    errors += test_byte_writes();
    errors += test_write_read_order();
    errors += test_dense_writes();

    if (errors == 0) PRINTF("axi_traffic: ALL PASSED\n");
    else             PRINTF("axi_traffic: FAILED (%d errors)\n", errors);

    // Pass/fail sentinel for UVM Gate-2 absolute-correctness check.
    *((volatile int*)RESULT_ADDR) = (errors == 0) ? 0x900DCAFE : errors;

    return errors;
}
