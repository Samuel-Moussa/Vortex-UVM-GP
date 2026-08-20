// unit_storm — create GENUINE BACK-PRESSURE inside the core so the elastic-buffer
// flow-control conditions can be exercised.
//
// TARGET (measured on the 1CL bank of 2026-08-16): 24 of the 46 missing condition
// input terms — 52% of the entire condition gap — are ONE expression replicated
// across 12 buffer instances:
//
//     VX_stream_buffer.sv:59   else if (valid_in || flow_out)
//     VX_stream_buffer.sv:54   wire flow_out = ready_out || ~valid_out;
//
// Focused-expression coverage needs each input term to independently determine the
// result. `flow_out` alone already does (it is 1 whenever the buffer is drained).
// The MISSING term is `valid_in`, and it can only be the deciding input when
// flow_out is 0 — which requires `ready_out == 0 && valid_out == 1`, i.e. the
// buffer is holding valid data that the consumer will not take.
//
// => this is not a "run it longer" gap. Nothing gets covered until the design is
//    actually congested. That makes it real verification work rather than metric
//    chasing: we are exercising flow control that the suite has never stressed.
//
// THE 12 STARVED BUFFERS AND WHY EACH SHOULD BACK-PRESSURE HERE:
//   4x local_mem/rsp_xbar/g_xbar_arbs[0..3]/.../out_buf
//        LMEM_NUM_BANKS = NUM_LSU_LANES (VX_config.vh:681), and consecutive words
//        map to different banks, so ONE thread issuing independent loads to 4
//        consecutive words puts 4 banks in flight simultaneously. They all respond
//        to the SAME requester, contend at that output arbiter, and the losers sit
//        with valid data while ready_out is low. This is the cleanest of the set.
//   1x mem_unit/lmem_arb/g_rsp_arb/req_arb/.../out_buf      (same traffic, one level up)
//   2x g_mem_bus_if[0]/g_i0/mem_arb/g_rsp_select/rsp_switch/g_out_buf[0..1]/out_buf
//        icache and dcache responses arriving together -> the L1 response switch
//        must stall one of them. Needs concurrent fetch pressure + data misses.
//   1x dcache/.../bank/core_rsp_queue                       (dcache responses out-run the LSU)
//   1x alu_unit/g_blocks[0]/pe_switch/rsp_arb/.../out_buf   (ALU results contending for commit)
//   2x sfu_unit/dispatch_unit/g_blocks[0]/buf_out, wctl_unit/rsp_buf
//   1x issue/g_slices[0]/issue_slice/dispatch/g_buffers[4]/buffer
//        EX_TCU = 4 (VX_gpu_pkg.sv:120) -> this is the TCU dispatch buffer and it
//        needs back-to-back WMMA. NOT attempted here: the TCU tile geometry is a
//        TEMPLATE argument (OBS-029) and getting it wrong produces a green run that
//        verifies nothing. Left for a dedicated TCU kernel.
//
// STRATEGY: keep every execution unit in flight at once so the single commit port
// (ISSUE_WIDTH=1) becomes the bottleneck. Congestion then propagates BACKWARDS into
// exactly these response buffers. Each iteration issues, with no dependence between
// them: 4 local-memory loads (4 banks), 2 global loads (dcache), FP work, integer
// work, and an SFU CSR read.
//
// DETERMINISM / SAFETY:
//   * every thread writes ONLY out_buf[i]; vx_spawn distributes CONTIGUOUSLY
//     (vx_spawn.c:299), so no barrier is needed and no core touches another's slice;
//   * local memory is PER-CORE, so identical offsets on different cores cannot
//     collide by construction;
//   * global reads come from a CONST .rodata table — read-only, so multi-core is
//     race-free by construction and no whole-array init is needed (OBS-026);
//   * all FP values are small integers held exactly in binary32, so the compare is
//     byte-exact with no tolerance;
//   * out_buf is .bss (already zero) and is never bulk-initialised.

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define ITERS      48
#define LM_SLOTS   8      // 8 consecutive words -> spans all LMEM banks twice
// ⚠ 4 KB, NOT BIGGER — this is a MEASURED choice, not an oversight.
// A v3 of this kernel used a 64 KB table (4x the dcache) with prime strides to
// force real dcache misses, aiming at mem_arb/rsp_switch and dcache/core_rsp_queue.
// Result: it gained NOTHING new and LOST wctl_unit/rsp_buf (2->0), scoring 11 terms
// against this version's 13. Heavy memory stalls did not add congestion, they
// SHIFTED the timing balance — the warps spent their time waiting on memory instead
// of issuing SFU ops densely enough to back up the WCTL response buffer.
// Lesson worth keeping: for flow-control coverage, ISSUE DENSITY beats memory volume.
#define TAB_WORDS  1024   // 4 KB const table -> stays resident, keeps issue density high
#define MAX_TOTAL  256

// Const table in .rodata: read-only => multi-core safe with no initialisation.
// Values are a simple deterministic sequence so the host reference can recompute
// them without reading device memory.
static const int g_tab[TAB_WORDS] = {
#define R1(i)  ((i) * 2654435761u) >> 16
#define R8(i)  R1(i), R1(i+1), R1(i+2), R1(i+3), R1(i+4), R1(i+5), R1(i+6), R1(i+7)
#define R64(i) R8(i), R8(i+8), R8(i+16), R8(i+24), R8(i+32), R8(i+40), R8(i+48), R8(i+56)
#define R512(i) R64(i), R64(i+64), R64(i+128), R64(i+192), R64(i+256), R64(i+320), R64(i+384), R64(i+448)
	R512(0), R512(512)
};

typedef struct { int *out; } us_args_t;

volatile int out_buf[MAX_TOTAL];

static inline int tab_ref(int i) { return (int)(((unsigned)i * 2654435761u) >> 16); }

void us_kernel(us_args_t *__UNIFORM__ args) {
	int i = blockIdx.x;

	// Per-CORE local-memory slice: local memory is core-private, so deriving the
	// base from the hardware ids (not the global task id) is what keeps two cores
	// from aliasing each other's scratchpad.
	volatile int *lm = (volatile int *)csr_read(VX_CSR_LOCAL_MEM_BASE);
	int base = ((vx_warp_id() * vx_num_threads()) + vx_thread_id()) * LM_SLOTS;

	for (int s = 0; s < LM_SLOTS; s++) lm[base + s] = s + 1;

	int acc = 0;
	float f = 0.0f;

	for (int k = 0; k < ITERS; k++) {
		// --- 4 INDEPENDENT local-memory loads, 4 consecutive words = 4 banks ---
		// Independent by construction (no data dependence between them), so the LSU
		// can have all four outstanding and all four banks respond together.
		int l0 = lm[base + 0];
		int l1 = lm[base + 1];
		int l2 = lm[base + 2];
		int l3 = lm[base + 3];

		// --- 2 global loads, far apart so they land on different cache lines ---
		int idx0 = (i * 7 + k * 17) & (TAB_WORDS - 1);
		int idx1 = (i * 13 + k * 101 + 512) & (TAB_WORDS - 1);
		int g0 = g_tab[idx0];
		int g1 = g_tab[idx1];

		// --- SFU BURST: back-to-back SFU ops to fill the SFU dispatch buffer ---
		// One csrr per iteration was not enough: measured at 1CL, unit_storm v1
		// covered the whole local-memory path but left
		//   sfu_unit/dispatch_unit/g_blocks[0]/buf_out  and
		//   sfu_unit/wctl_unit/rsp_buf                  at 0/2.
		// Those need the SFU's own buffers to hold a valid op while the SFU is busy,
		// i.e. SFU ops issued faster than they retire. Four back-to-back reads of
		// DIFFERENT CSRs cannot be CSE'd into one and keep the SFU pipe occupied.
		// All four are topology constants the host can also read, so the result
		// stays exactly predictable.
		int c0 = (int)vx_num_warps();
		int c1 = (int)vx_num_threads();
		int c2 = (int)vx_num_warps();
		int c3 = (int)vx_num_threads();
		// vx_pred is a WCTL (warp-control) op -> exercises wctl_unit/rsp_buf.
		// The condition is UNIFORMLY TRUE and the mask is the full thread mask, so
		// the active set is unchanged and control flow is not perturbed (the same
		// argument multicore_isa relies on). Two in a row so the response buffer
		// sees a second op arrive while the first is still in flight.
		// NOTE on the 0xF: vx_pred's 2nd argument is the FALLBACK mask, used only
		// when NO thread satisfies the condition (vx_intrinsics.h:118). The condition
		// here is the literal 1, so that case cannot arise and the value is a
		// don't-care — which is why this stays correct at any NUM_THREADS. Same
		// reasoning multicore_isa relies on.
		vx_pred(1, 0xF);
		vx_pred(1, 0xF);

		// --- SFU: a CSR read that occupies the SFU pipe every iteration --------
		// ⚠ FIRST VERSION USED `(void)vx_warp_id();` AND THE READ VANISHED. The
		// disassembly showed only the four setup csrr's and NONE inside the loop —
		// an unused volatile-asm result was still eliminated. A kernel whose
		// stimulus the compiler deleted is the OBS-029 failure mode in miniature:
		// it would have run green and driven nothing.
		// Fix: make the value DATA-DEPENDENT so it cannot be removed, using a CSR
		// the host can also read (NUM_WARPS is uniform across cores, unlike warp id).
		int nwv = (int)vx_num_warps();

		// --- FPU: exact small-integer FP so the result compares byte-exact -----
		f = f + 1.0f;

		// --- ALU: fold everything; the adds cannot start until the loads return,
		//     which is what makes the results pile up at the commit port --------
		acc += (l0 + l1 + l2 + l3) ^ (g0 + g1) ^ nwv ^ (c0 + c1 + c2 + c3);

		// Rotate the scratchpad so the next iteration's loads are not forwarded
		// from a store buffer and must go to the banks again.
		lm[base + (k & (LM_SLOTS - 1))] = acc + k;
	}

	args->out[i] = acc + (int)f;
}

// Host reference — recomputes the identical recurrence with no device state.
static int us_ref(int i, int nwv, int ntv) {
	int lmv[LM_SLOTS];
	for (int s = 0; s < LM_SLOTS; s++) lmv[s] = s + 1;
	int acc = 0;
	float f = 0.0f;
	for (int k = 0; k < ITERS; k++) {
		int l0 = lmv[0], l1 = lmv[1], l2 = lmv[2], l3 = lmv[3];
		int idx0 = (i * 7 + k * 17) & (TAB_WORDS - 1);
		int idx1 = (i * 13 + k * 101 + 512) & (TAB_WORDS - 1);
		int g0 = tab_ref(idx0);
		int g1 = tab_ref(idx1);
		f = f + 1.0f;
		acc += (l0 + l1 + l2 + l3) ^ (g0 + g1) ^ nwv ^ (2*nwv + 2*ntv);
		lmv[k & (LM_SLOTS - 1)] = acc + k;
	}
	return acc + (int)f;
}

int main() {
	us_args_t args;
	args.out = (int *)out_buf;

	uint32_t total = (uint32_t)vx_num_cores() * vx_num_warps() * (uint32_t)vx_num_threads();
	if (total > MAX_TOTAL) total = MAX_TOTAL;
	vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)us_kernel, &args);

	// Verify ONLY this core's contiguous slice (vx_spawn.c:299).
	uint32_t nc = (uint32_t)vx_num_cores(), cid = (uint32_t)vx_core_id();
	uint32_t per = total / nc, lo = cid * per, hi = lo + per;
	int errors = 0;
	for (uint32_t i = lo; i < hi; i++) {
		if (out_buf[i] != us_ref((int)i, (int)vx_num_warps(), (int)vx_num_threads())) errors++;
	}
	return errors;
}
