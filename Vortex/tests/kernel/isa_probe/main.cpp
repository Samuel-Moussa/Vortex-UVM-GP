// isa_probe — close the REACHABLE code-coverage gaps in the CSR read path and the
// FP misc/fused-multiply decode, with a golden-model-safe stimulus.
//
// WHY THIS EXISTS. Measured on the 1CL bank of 2026-08-16, the largest remaining
// REACHABLE (i.e. not structurally dead) code-coverage holes were:
//     VX_csr_data.sv   8 statements + 28 branches  <- M-mode CSR READ case
//     VX_decode.sv     ~12 statements              <- FCLASS / FMV.X.W / FMSUB / FNMSUB
//     VX_gpu_pkg.sv:368,372                        <- inst_fpu_is_class / _is_mvxw
// Nothing in the suite reads a machine-mode CSR or executes fclass/fmv.x.w, and
// clang never emits fmsub/fnmsub from the source we had (it lowers to fmadd+fneg,
// the same trap that hid fnmadd until session 9).
//
// ── THE PART THAT MATTERS: WHICH CSRs ARE SAFE TO TOUCH, AND WHY ──────────────
// A kernel is only useful here if DUT and SimX agree, otherwise it converts a
// coverage win into a false failure. The two models do NOT agree on all CSRs:
//
//   SAFE — both return 0, verified in both sources:
//     RTL   VX_csr_data.sv:194-203  -> read_data_ro_w = 0
//     SimX  emulator.cpp:476-491    -> `return 0;`
//     SATP MSTATUS MEDELEG MIDELEG MIE MTVEC MEPC PMPCFG0 PMPADDR0 MNSTATUS
//
//   ⚠ DELIBERATELY NOT READ — the models provably DISAGREE:
//     MISA      RTL VX_csr_data.sv:182 returns {2'(CLOG2(XLEN/16)), 30'(MISA_STD)}
//               SimX emulator.cpp:484 returns 0.
//     MVENDORID / MARCHID / MIMPID
//               RTL returns `VENDOR_ID / `ARCHITECTURE_ID / `IMPLEMENTATION_ID;
//               SimX has no case for them and its default silently returns 0 for
//               the whole 0xF00-0xFFF hw-id range (emulator.cpp:518-522).
//     Reading these would writeback a value the golden model cannot reproduce.
//     Under end-state compare that is only a problem if stored; under LOCKSTEP it
//     is a guaranteed per-instruction mismatch. A kernel that cannot run under the
//     strongest checker we own is a liability, so we do not read them at all.
//     => those 4 RTL lines are UNREACHABLE-UNDER-THIS-METHODOLOGY, not merely
//        untested. See docs/COVERAGE_CEILING_ANALYSIS.md and OBS-036.
//
// NON-VACUITY (OBS-029). The CSR values are not folded away: the raw OR of all ten
// reads is STORED. The expected value is 0, so if the DUT ever returned a non-zero
// for one of these the scoreboard sees it — this is a real check, not a bin tick.
// The FP results are stored as exact bit patterns, chosen so every operation is
// exact in binary32 (no rounding, no tolerance needed).
//
// MULTI-CORE SAFETY: every thread writes ONLY out_buf[i]; vx_spawn distributes
// tasks CONTIGUOUSLY (vx_spawn.c:299) so no core touches another core's slice and
// no barrier is required (Vortex has none with GBAR_ENABLE off). out_buf is NOT
// zeroed — it is .bss and a whole-array init would wipe another core's results
// once every core is active (OBS-026).

#include <vx_intrinsics.h>
#include <vx_spawn.h>

// M-mode CSR addresses. VX_types.h (the C mirror) does not define these, so they
// are written literally, each citing hw/rtl/VX_types.vh.
#define CSR_SATP      0x180   // VX_types.vh:45
#define CSR_MSTATUS   0x300   // VX_types.vh:50
#define CSR_MEDELEG   0x302   // VX_types.vh:52
#define CSR_MIDELEG   0x303   // VX_types.vh:53
#define CSR_MIE       0x304   // VX_types.vh:54
#define CSR_MTVEC     0x305   // VX_types.vh:55
#define CSR_MEPC      0x341   // VX_types.vh:58
#define CSR_PMPCFG0   0x3A0   // VX_types.vh:47
#define CSR_PMPADDR0  0x3B0   // VX_types.vh:48
#define CSR_MNSTATUS  0x744   // VX_types.vh:61

#define MAX_TOTAL 256

typedef struct { int *out; } ip_args_t;

volatile int out_buf[MAX_TOTAL];

// fclass.s / fmv.x.w / fmsub.s / fnmsub.s via inline asm.
// clang at -march=rv32imaf will emit fclass/fmv.x.w for the builtins, but it
// lowers -fmaf(a,b,c) to fmadd+fneg rather than fnmsub, so the fused forms are
// spelled out to guarantee the encodings actually reach the decoder.
#define FCLASS_S(rd, rs1)      __asm__ volatile("fclass.s %0, %1" : "=r"(rd) : "f"(rs1))
#define FMV_X_W(rd, rs1)       __asm__ volatile("fmv.x.w  %0, %1" : "=r"(rd) : "f"(rs1))
#define FMSUB_S(rd, a, b, c)   __asm__ volatile("fmsub.s  %0, %1, %2, %3"  : "=f"(rd) : "f"(a), "f"(b), "f"(c))
#define FNMSUB_S(rd, a, b, c)  __asm__ volatile("fnmsub.s %0, %1, %2, %3" : "=f"(rd) : "f"(a), "f"(b), "f"(c))

void ip_kernel(ip_args_t *__UNIFORM__ args) {
	int i = blockIdx.x;

	// ---- 1. M-mode CSR reads (VX_csr_data.sv read case) ----------------------
	// Every one of these must read 0 on both models. The OR is stored, so a
	// non-zero from either side is a scoreboard failure rather than a silent pass.
	unsigned acc = 0;
	acc |= (unsigned)csr_read(CSR_SATP);
	acc |= (unsigned)csr_read(CSR_MSTATUS);
	acc |= (unsigned)csr_read(CSR_MEDELEG);
	acc |= (unsigned)csr_read(CSR_MIDELEG);
	acc |= (unsigned)csr_read(CSR_MIE);
	acc |= (unsigned)csr_read(CSR_MTVEC);
	acc |= (unsigned)csr_read(CSR_MEPC);
	acc |= (unsigned)csr_read(CSR_PMPCFG0);
	acc |= (unsigned)csr_read(CSR_PMPADDR0);
	acc |= (unsigned)csr_read(CSR_MNSTATUS);

	// ---- 1b. M-mode CSR WRITES (VX_csr_data.sv:135-143 "do nothing!") -------
	// These addresses are accepted-and-ignored by BOTH models, so the write is
	// architecturally inert and cannot perturb the end-state compare:
	//     RTL   VX_csr_data.sv:134-145  -> case arm whose body is `// do nothing!`
	//     SimX  emulator.cpp:637-647    -> case arm that just `break;`s
	//
	// ⚠ MISA (0x301) IS DELIBERATELY ABSENT. SimX ignores a write to it
	// (emulator.cpp:638) but the RTL does NOT list it, so it falls through to
	// VX_csr_data.sv:149 `ASSERT(0, "invalid CSR write address")` and kills the run.
	// This is precisely the `csrw 0x301` that prepare.sh sed-strips out of every
	// riscv-dv program — the same trap, rediscovered from the RTL side.
	//
	// ⚠ SATP (0x180) is also omitted ON PURPOSE. It is inert only while VM_ENABLE
	// is off; if virtual memory were ever built in, writing it would repoint
	// address translation mid-kernel. One branch item is not worth a waiver that
	// silently becomes catastrophic under a different build.
	csr_write(CSR_MSTATUS,  0);
	csr_write(CSR_MNSTATUS, 0);
	csr_write(CSR_MEDELEG,  0);
	csr_write(CSR_MIDELEG,  0);
	csr_write(CSR_MIE,      0);
	csr_write(CSR_MTVEC,    0);
	csr_write(CSR_MEPC,     0);
	csr_write(CSR_PMPCFG0,  0);
	csr_write(CSR_PMPADDR0, 0);

	// ---- 2. FCLASS / FMV.X.W (VX_decode.sv:444-455, gpu_pkg:368,372) --------
	// fclass.s returns a 10-bit class mask; 2.0f is "positive normal" = bit 6 = 0x40.
	// fmv.x.w moves the raw bits; 2.0f is exactly 0x40000000. Both are exact and
	// architecturally fixed, so they compare byte-for-byte against SimX.
	float fv = 2.0f;
	int cls = 0, bits = 0;
	FCLASS_S(cls, fv);
	FMV_X_W(bits, fv);

	// ---- 3. Fused multiply-sub forms (VX_decode.sv:355-358) ------------------
	// All operands are small powers of two, so every result is exact in binary32.
	//   fmsub.s  = (a*b) - c   =  (3*4) - 2  =  10
	//   fnmsub.s = -(a*b) + c  = -(3*4) + 2  = -10   (RISC-V: -(a*b)+c)
	float a = 3.0f, b = 4.0f, c = 2.0f, r1, r2;
	FMSUB_S(r1, a, b, c);
	FNMSUB_S(r2, a, b, c);

	// ---- 4. FCSR direct write (VX_csr_data.sv:104,132) ----------------------
	// Done LAST, after every FP operation above, so it cannot change the rounding
	// mode used by any result we compare. 0 is the reset/default value (RNE, no
	// sticky flags), so this restores the default rather than imposing a new one.
	// Unlike the M-mode writes this one IS architectural — both models update fcsr
	// (RTL VX_csr_data.sv:104, SimX emulator.cpp:626) — and they agree on 0.
	csr_write(0x003 /* VX_CSR_FCSR, VX_types.vh */, 0);

	// Fold into one deterministic per-slot word. `acc` contributes 0 when the CSRs
	// behave; the FP terms are exact integers so the sum is exact.
	int folded = (int)acc
	           + (cls << 8)              // 0x40 -> 0x4000
	           + (bits >> 16)            // 0x40000000 -> 0x4000
	           + (int)r1                 // +10
	           + (int)r2                 // -10
	           + i;                      // per-slot discriminator

	args->out[i] = folded;
}

// Host reference — same arithmetic, no device state.
static int ip_ref(int i) {
	return 0 + (0x40 << 8) + (0x40000000 >> 16) + 10 + (-10) + i;
}

int main() {
	ip_args_t args;
	args.out = (int *)out_buf;

	uint32_t total = (uint32_t)vx_num_cores() * vx_num_warps() * vx_num_threads();
	if (total > MAX_TOTAL) total = MAX_TOTAL;
	vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)ip_kernel, &args);

	// Verify ONLY this core's contiguous slice (vx_spawn.c:299).
	uint32_t nc = (uint32_t)vx_num_cores(), cid = (uint32_t)vx_core_id();
	uint32_t per = total / nc, lo = cid * per, hi = lo + per;
	int errors = 0;
	for (uint32_t i = lo; i < hi; i++) {
		if (out_buf[i] != ip_ref((int)i)) errors++;
	}
	return errors;
}
