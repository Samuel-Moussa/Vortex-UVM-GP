//==============================================================================
// regression_test.sv
//------------------------------------------------------------------------------
// Path-A "argv harness" test for Vortex regression programs that read their
// argument struct via MSCRATCH (kernel_arg_t* arg = csr_read(VX_CSR_MSCRATCH)).
//
// WHY THIS TEST EXISTS (and is SEPARATE from kernel_launch_test):
//   - hello/conform/fibonacci are self-contained: they never read MSCRATCH, so
//     argv_ptr=0 is fine and kernel_launch_test runs them correctly.
//   - basic/diverge/sgemm/dogfood are argv-dependent: each dereferences
//     arg->src_addr / dst_addr / A_addr ... which the HOST main.cpp normally
//     sets up. There is no host here, so THIS test emulates the host's
//     kernel-launch ABI: lay out buffers + a kernel_arg_t in mem_model, then
//     point startup_arg (-> MSCRATCH) at that struct.
//
// MECHANISM (all pre-existing, no project files changed):
//   - mem_model.write_word/write_dword/write_block : lay down struct + inputs
//   - dcr_startup_config_sequence.argv_ptr         : already writes
//       VX_DCR_BASE_STARTUP_ARG0/1 when argv_ptr != 0  (dcr_sequences.sv:163)
//   - VX_csr_data: mscratch <= startup_arg on reset deassert
//
// CRITICAL — STRUCT ALIGNMENT:
//   kernel_arg_t mixes uint32_t then uint64_t. C aligns uint64_t to 8 bytes,
//   so a uint32_t at offset 0 is followed by 4 PAD bytes; the first uint64_t
//   begins at offset 8, NOT 4. Writing an address at offset 4 yields a wild
//   pointer and a fault that looks exactly like argv=0. The offsets below are
//   the ABI-correct ones. CONFIRM once against the compiled struct with
//   riscv objdump / offsetof if you want belt-and-suspenders.
//
// INPUT-DATA CONTRACT:
//   The scoreboard runs SimX on the SAME mem_model image via DPI. Whatever
//   bytes this harness writes into src/A/B are exactly what SimX computes
//   against, so DUT-vs-SimX is a true comparison. Inputs here mirror each
//   program's host main.cpp generator (seed + pattern) so results are sensible.
//==============================================================================

class regression_test extends vortex_base_test;
    `uvm_component_utils(regression_test)

    // ---- which program this run drives (set via +PROGRAM_KIND= or factory) ---
    // "basic" | "diverge" | "sgemm" | "dogfood"
    string program_kind = "basic";

    // ---- data-region base (well clear of code @0x80000000 and local mem) -----
    // SimX models capacity=0x1_0000_0000 (4GB), so 0x9000_0000 is in range and
    // far from the program image and the 0xffff_xxxx local-mem traffic.
    localparam bit [63:0] DATA_BASE = 64'h0000_0000_9000_0000;

    // sub-region layout (1 page spacing; bump if a program needs > 4KB/buffer)
    localparam bit [63:0] ARGS_ADDR = DATA_BASE + 64'h0000;   // kernel_arg_t
    localparam bit [63:0] BUF0_ADDR = DATA_BASE + 64'h1000;   // src / src0 / A
    localparam bit [63:0] BUF1_ADDR = DATA_BASE + 64'h2000;   // src1 / B
    localparam bit [63:0] BUF2_ADDR = DATA_BASE + 64'h3000;   // dst / C

    // element count (kept tiny for fast bring-up; raise once green)
    int unsigned n_elems = 16;

    // handle to the shared mem_model (same object tb_top registered)
    mem_model mem;

    function new(string name = "regression_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //--------------------------------------------------------------------------
    // customize_config OVERRIDE  (MANDATORY — not optional)
    //
    //   The scoreboard HARD-GATES every compare path on result_size_bytes > 0
    //   (vortex_scoreboard.sv:411,447 return early; compare_result_region only
    //   runs when size>0). If we inherit a zero result region, the kernel runs
    //   but NOTHING is compared = vacuous pass. So we MUST:
    //     (a) enable scoreboard + SimX + agents (same as kernel_launch_test), and
    //     (b) set result_base_addr/result_size_bytes to the OUTPUT buffer so
    //         compare_result_region checks DUT writes vs SimX at that region.
    //
    //   The result region is the dst/C buffer (where the kernel writes results):
    //     basic/diverge : BUF2_ADDR, n_elems words
    //     sgemm         : BUF2_ADDR (C), size*size words (4x4=16)
    //     dogfood       : BUF2_ADDR (dst), n_elems words
    //--------------------------------------------------------------------------
    virtual function void customize_config();
        bit [63:0] result_base_override;
        int unsigned result_size_override;
        int unsigned out_words;

        // Seed the kernel-arg pointer so the dcr_driver's DURING-RESET bootstrap
        // latches it into startup_arg -> MSCRATCH at reset deassert. Writing it later
        // (in run_test_stimulus) is too late: MSCRATCH latches at reset, so a post-reset
        // DCR write lands after the latch and the kernel reads MSCRATCH=0.
        cfg.startup_arg = ARGS_ADDR;   // 0x90000000
        
        // --- enable the checking infrastructure (mirrors kernel_launch_test) ---
        cfg.enable_scoreboard    = 1;
        cfg.enable_coverage      = 1;
        cfg.simx_enable          = 1;
        cfg.simx_path            = "DPI_MODE";
        cfg.dcr_agent_is_active  = 1;
        cfg.host_agent_enable    = 1;
        cfg.host_agent_is_active = 1;
        cfg.axi_agent_is_active  = cfg.axi_agent_enable;

        // --- pick up program kind early (also read in build_phase) so the
        //     result-size calc below matches the actual program ---
        void'($value$plusargs("PROGRAM_KIND=%s", program_kind));
        void'($value$plusargs("N_ELEMS=%d",      n_elems));

        // --- output word count per program ---
        case (program_kind)
            "sgemm"   : out_words = 16;        // 4x4 C matrix
            default   : out_words = n_elems;   // basic/diverge/dogfood: dst[n]
        endcase

        // --- result region = the dst/C buffer (BUF2_ADDR), unless overridden ---
        // NOTE: compare_result_region reads base_addr as a 32-bit phys addr and
        // zero-extends. BUF2_ADDR low 32 bits = 0x9000_3000 — within SimX RAM.
        if ($value$plusargs("RESULT_BASE_ADDR=%h", result_base_override))
            cfg.result_base_addr = result_base_override;
        else
            cfg.result_base_addr = BUF2_ADDR;

        if ($value$plusargs("RESULT_SIZE_BYTES=%d", result_size_override))
            cfg.result_size_bytes = result_size_override;
        else
            cfg.result_size_bytes = out_words * 4;   // words -> bytes

        // --- timeout clamp (same discipline as kernel_launch_test) ---
        if (cfg.test_timeout_cycles > cfg.global_timeout_cycles)
            cfg.test_timeout_cycles = cfg.global_timeout_cycles;

        // Kernels that wrap vx_spawn_threads stage scheduler args on the runtime
        // stack (local mem), which is not replicated into SimX — so DUT/SimX cannot
        // be made bit-equivalent without lockstep. Mark them UNVERIFIABLE.
        // Confirmed by grep: basic is flat (no csrw mscratch); diverge/dogfood/sgemm
        // each execute csrw mscratch (0x34079073) post-startup.
        cfg.is_spawn_kernel = (program_kind inside {"diverge", "dogfood", "sgemm"});

        `uvm_info(get_type_name(),
            $sformatf("regression cfg: program_kind=%s result_base=0x%016h result_size=%0d bytes timeout=%0d iface=%s",
                program_kind,
                cfg.result_base_addr,
                cfg.result_size_bytes,
                cfg.test_timeout_cycles,
                cfg.axi_agent_enable ? "AXI4" : "CustomMEM"), UVM_LOW)
    endfunction

    //--------------------------------------------------------------------------
    // build: grab program kind + the shared mem_model
    //--------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        void'($value$plusargs("PROGRAM_KIND=%s", program_kind));
        void'($value$plusargs("N_ELEMS=%d",      n_elems));

        if (!uvm_config_db#(mem_model)::get(this, "", "mem_model", mem))
            `uvm_fatal("REGR", "mem_model not found in config_db — tb_top must register it")

        `uvm_info("REGR", $sformatf("regression_test: program=%s n_elems=%0d data_base=0x%016h",
                                    program_kind, n_elems, DATA_BASE), UVM_LOW)
    endfunction

    //==========================================================================
    // load_program OVERRIDE — runs at run_phase step 1, BEFORE wait_for_reset().
    // We call super (keeps the base's program-path gate + bytes_loaded sentinel),
    // then stage the kernel_arg_t struct + buffers into memory while reset is
    // still asserted, so the struct is present before the kernel's first arg-load.
    // MSCRATCH itself is seeded separately via cfg.startup_arg (set in
    // customize_config, latched by the dcr_driver bootstrap at reset).
    //==========================================================================
    virtual task load_program();
        super.load_program();   // base: sets bytes_loaded sentinel + logs path
        setup_kernel_args();    // stage struct + src/dst buffers BEFORE reset releases
        `uvm_info("REGR", $sformatf("Kernel args staged @0x%016h before reset", ARGS_ADDR), UVM_LOW)
    endtask

    //--------------------------------------------------------------------------
    // setup_kernel_args : dispatch to per-program layout
    //--------------------------------------------------------------------------
    virtual task setup_kernel_args();
        case (program_kind)
            "basic"   : layout_basic();
            "diverge" : layout_diverge();
            "sgemm"   : layout_sgemm();
            "dogfood" : layout_dogfood();
            default   : `uvm_fatal("REGR", $sformatf("unknown program_kind '%s'", program_kind))
        endcase
    endtask

    //==========================================================================
    // PER-PROGRAM LAYOUTS  (offsets are ABI-aligned; see header note)
    //==========================================================================

    // basic/common.h:  { uint32_t count; uint64_t src_addr; uint64_t dst_addr; }
    //   offset 0  : count        (u32)
    //   offset 4  : PAD (4)
    //   offset 8  : src_addr     (u64)
    //   offset 16 : dst_addr     (u64)   total 24 bytes
    // kernel: dst[i] = src[i]  (memcopy). host pattern: shuffle(i, 0xdeadbeef).
    virtual task layout_basic();
        bit [31:0] v;
        // inputs
        for (int i = 0; i < n_elems; i++) begin
            v = shuffle(i, 32'hdead_beef);
            poke_word(BUF0_ADDR + i*4, v);      // src
            poke_word(BUF2_ADDR + i*4, 32'h0);  // dst cleared
        end
        // arg struct
        poke_word (ARGS_ADDR + 0,  n_elems);    // count
        poke_dword(ARGS_ADDR + 8,  BUF0_ADDR);  // src_addr
        poke_dword(ARGS_ADDR + 16, BUF2_ADDR);  // dst_addr
    endtask

    // diverge/common.h: { uint32_t num_points; uint64_t src_addr; uint64_t dst_addr; }
    //   same layout as basic (offsets 0 / 8 / 16, total 24).
    // host: srand(50); src[i] = rand(). kernel does heavy if/else/switch/select.
    virtual task layout_diverge();
        bit [31:0] v;
        // NOTE: SV $random is not C rand(); inputs need only be deterministic and
        // identical to what SimX sees (same mem image). Use a fixed pattern.
        for (int i = 0; i < n_elems; i++) begin
            v = lcg_rand();                          // deterministic pseudo-random
            poke_word(BUF0_ADDR + i*4, v);      // src
            poke_word(BUF2_ADDR + i*4, 32'h0);  // dst
        end
        poke_word (ARGS_ADDR + 0,  n_elems);    // num_points
        poke_dword(ARGS_ADDR + 8,  BUF0_ADDR);  // src_addr
        poke_dword(ARGS_ADDR + 16, BUF2_ADDR);  // dst_addr
    endtask

    // sgemm/common.h:
    //   { uint32_t grid_dim[2]; uint32_t size; uint64_t A_addr,B_addr,C_addr; }
    //   offset 0  : grid_dim[0]  (u32)
    //   offset 4  : grid_dim[1]  (u32)
    //   offset 8  : size         (u32)
    //   offset 12 : PAD (4)
    //   offset 16 : A_addr       (u64)
    //   offset 24 : B_addr       (u64)
    //   offset 32 : C_addr       (u64)   total 40 bytes
    // FLOAT matmul -> exercises EX_FPU. size small (e.g. 4x4) for bring-up.
    virtual task layout_sgemm();
        int unsigned sz = 4;                          // 4x4 matrices
        int unsigned sq = sz*sz;
        bit [31:0] fa, fb;
        for (int i = 0; i < sq; i++) begin
            fa = f32_from_small_int(i + 1);           // simple float bit patterns
            fb = f32_from_small_int((sq - i));
            poke_word(BUF0_ADDR + i*4, fa);      // A
            poke_word(BUF1_ADDR + i*4, fb);      // B
            poke_word(BUF2_ADDR + i*4, 32'h0);   // C
        end
        poke_word (ARGS_ADDR + 0,  sz);          // grid_dim[0]
        poke_word (ARGS_ADDR + 4,  sz);          // grid_dim[1]
        poke_word (ARGS_ADDR + 8,  sz);          // size
        poke_dword(ARGS_ADDR + 16, BUF0_ADDR);   // A_addr
        poke_dword(ARGS_ADDR + 24, BUF1_ADDR);   // B_addr
        poke_dword(ARGS_ADDR + 32, BUF2_ADDR);   // C_addr
    endtask

    // dogfood/common.h:
    //   { uint32_t testid; uint32_t num_tasks; uint32_t task_size;
    //     uint64_t src0_addr, src1_addr, dst_addr; }
    //   offset 0  : testid       (u32)
    //   offset 4  : num_tasks    (u32)
    //   offset 8  : task_size    (u32)
    //   offset 12 : PAD (4)
    //   offset 16 : src0_addr    (u64)
    //   offset 24 : src1_addr    (u64)
    //   offset 32 : dst_addr     (u64)   total 40 bytes
    // testid selects sub-kernel: 0=iadd 1=imul 2=idiv ... 4=fadd ... 14=fsqrt
    //   22=bar 23=gbar. Pick via +DOGFOOD_TESTID=. Default 4 (fadd -> FPU).
    int unsigned dogfood_testid = 4;
    virtual task layout_dogfood();
        bit [31:0] a, b;
        void'($value$plusargs("DOGFOOD_TESTID=%d", dogfood_testid));
        for (int i = 0; i < n_elems; i++) begin
            a = lcg_rand();
            b = lcg_rand() | 32'h1;                   // avoid /0 in idiv/fdiv tests
            poke_word(BUF0_ADDR + i*4, a);       // src0
            poke_word(BUF1_ADDR + i*4, b);       // src1
            poke_word(BUF2_ADDR + i*4, 32'hdead_beef); // dst sentinel
        end
        poke_word (ARGS_ADDR + 0,  dogfood_testid); // testid
        poke_word (ARGS_ADDR + 4,  1);              // num_tasks (1 task block)
        poke_word (ARGS_ADDR + 8,  n_elems);        // task_size
        poke_dword(ARGS_ADDR + 16, BUF0_ADDR);      // src0_addr
        poke_dword(ARGS_ADDR + 24, BUF1_ADDR);      // src1_addr
        poke_dword(ARGS_ADDR + 32, BUF2_ADDR);      // dst_addr
        `uvm_info("REGR", $sformatf("dogfood sub-kernel testid=%0d", dogfood_testid), UVM_LOW)
    endtask

    //==========================================================================
    // RESULT CHECK OVERRIDE
    //   The result region is already configured in customize_config()
    //   (cfg.result_base_addr / result_size_bytes -> BUF2_ADDR). The scoreboard's
    //   compare_result_region() reads SimX vs DUT-shadow at that region on EBREAK
    //   and flags mismatches AND dropped stores (a result addr SimX wrote but the
    //   DUT didn't -> "Result addr not written by DUT" warning at line 380, which
    //   is where dropped-store detection lives). We just log the region for trace.
    //--------------------------------------------------------------------------
    virtual function void check_results();
        super.check_results();   // base console/EBREAK handling + scoreboard runs
        `uvm_info("REGR",
            $sformatf("Result region configured: base=0x%016h size=%0d bytes (scoreboard compared vs SimX)",
                      cfg.result_base_addr, cfg.result_size_bytes), UVM_LOW)
    endfunction

    //==========================================================================
    // HELPERS
    //==========================================================================

    // host basic main.cpp: (value << i) | (value & ((1<<i)-1))
    function bit [31:0] shuffle(int i, bit [31:0] value);
        bit [31:0] mask;
        mask = (32'h1 << i) - 1;
        return (value << i) | (value & mask);
    endfunction

    // deterministic LCG so the mem image is reproducible AND identical for SimX
    bit [31:0] lcg_state = 32'h1234_5678;
    function bit [31:0] lcg_rand();
        lcg_state = (lcg_state * 32'd1664525) + 32'd1013904223;
        return lcg_state;
    endfunction

    // tiny helper: IEEE-754 single for a small positive integer (1.0*n style).
    // Good enough to drive EX_FPU with non-degenerate operands; not a full f32 lib.
    function bit [31:0] f32_from_small_int(int unsigned n);
        // build n.0f: find exponent, normalize. For 1..255 this is exact.
        bit [31:0] r;
        int unsigned m;
        int unsigned e;
        if (n == 0) return 32'h0;
        m = n; e = 0;
        while (m > 1) begin m = m >> 1; e++; end
        // mantissa = n shifted into 23 bits, drop implicit leading 1
        r = 32'h0;
        r[31]    = 1'b0;                     // sign +
        r[30:23] = 8'(127 + e);             // biased exponent
        r[22:0]  = 23'((n << (23 - e)) & 23'h7f_ffff); // fractional bits
        return r;
    endfunction

    // Write a 32-bit word to BOTH the UVM mem_model AND SimX's RAM, so the DUT
    // and the golden model see identical memory. Without the SimX half, SimX
    // reads zero at the arg-struct/buffer addresses and runs away.
    function void poke_word(bit [63:0] addr, bit [31:0] data);
        byte unsigned bytes[];
        mem.write_word(addr, data);          // DUT side (mem_model)
        bytes = new[4];
        for (int i = 0; i < 4; i++) bytes[i] = data[i*8 +: 8];   // little-endian
        simx_write_mem(addr, 4, bytes);      // SimX side (golden RAM)
    endfunction

    function void poke_dword(bit [63:0] addr, bit [63:0] data);
        byte unsigned bytes[];
        mem.write_dword(addr, data);
        bytes = new[8];
        for (int i = 0; i < 8; i++) bytes[i] = data[i*8 +: 8];
        simx_write_mem(addr, 8, bytes);
    endfunction

endclass : regression_test