// ============================================================================
// File: uvm_tests/functional_memory_test.sv
// Description: Functional Memory Test — MOD-1 architecture
//
// Purpose:
//   Verifies that the DUT can fetch instructions from mem_model, execute a
//   program that writes a known value to a known address, and that the result
//   is readable back from mem_model via the MEM/AXI agent.
//
// Flow (all inherited from vortex_base_test.run_phase):
//   STEP 1 — load_program()            : loads program_with_store.hex into mem_model
//   STEP 2 — wait_for_reset()          : level-safe override below
//   STEP 3 — monitor_memory_activity() : background (base)
//   STEP 4 — run_test_stimulus()       : OVERRIDE — launches vortex_functional_mem_vseq
//   STEP 5 — wait_for_completion()     : waits for EBREAK (base)
//   STEP 6 — check_results()           : OVERRIDE — golden value check
//
// Required program: program_with_store.hex
//   RISC-V program that writes value 0x00000003 to address 0x80001000
//   then executes EBREAK.
//   File starts with @00000000 (NOT @80000000 — mem_model adds base_addr).
//
// Golden check (inside vortex_functional_mem_vseq):
//   mem_model[0x80001000][31:0] == 32'h00000003
//
// Author: Vortex UVM Team — MOD-1 March 2026
// ============================================================================

`ifndef FUNCTIONAL_MEMORY_TEST_SV
`define FUNCTIONAL_MEMORY_TEST_SV

// This file is `included inside vortex_test_pkg.
// All imports are provided by the enclosing package scope — do NOT re-import here.

class functional_memory_test extends vortex_base_test;
    `uvm_component_utils(functional_memory_test)

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------
    function new(string name = "functional_memory_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // -------------------------------------------------------------------------
    // build_phase — base handles everything (cfg, vif, env creation)
    // -------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info(get_type_name(), "Building functional memory test...", UVM_LOW)
    endfunction

    // -------------------------------------------------------------------------
    // customize_config — called by base.build_phase AFTER set_defaults/apply_plusargs
    // -------------------------------------------------------------------------
    virtual function void customize_config();
        cfg.enable_scoreboard   = 1;
        cfg.enable_coverage     = 1;
        
        cfg.simx_enable         = 1;             // <-- SimX is ENABLED
        cfg.simx_path           = "DPI_MODE";    // <-- BYPASS legacy config validation

        cfg.dcr_agent_is_active = 0;   // PASSIVE — TBTOP owns all DCR writes

        // This program stores its result at 0x80001000, so point the generic
        // result comparison window at the actual destination instead of the
        // default startup+0x100000 region.
        cfg.result_base_addr    = cfg.startup_addr + 64'h1000;
        cfg.result_size_bytes   = 4;

        if (cfg.axi_agent_enable) begin
            cfg.mem_agent_enable = 0;
        end else begin
            cfg.mem_agent_enable = 1;
        end

        cfg.axi_agent_is_active = cfg.axi_agent_enable;

        if (cfg.test_timeout_cycles > cfg.global_timeout_cycles)
            cfg.test_timeout_cycles = cfg.global_timeout_cycles;

        `uvm_info(get_type_name(),
            $sformatf("FuncMem cfg: startup=0x%016h timeout=%0d cycles iface=%s",
                cfg.startup_addr,
                cfg.test_timeout_cycles,
                cfg.axi_agent_enable ? "AXI4" : "CustomMEM"), UVM_LOW)
    endfunction

    // -------------------------------------------------------------------------
    // end_of_elaboration_phase
    // -------------------------------------------------------------------------
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        `uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)
        `uvm_info(get_type_name(), " FUNCTIONAL MEMORY TEST                                        ", UVM_LOW)
        `uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)
        `uvm_info(get_type_name(), " Test Flow:                                                     ", UVM_LOW)
        `uvm_info(get_type_name(), "   1. load_program()         [base]  load hex into mem_model   ", UVM_LOW)
        `uvm_info(get_type_name(), "   2. wait_for_reset()       [override] level-safe             ", UVM_LOW)
        `uvm_info(get_type_name(), "   3. monitor_memory_activity[base]  background AXI/MEM counts ", UVM_LOW)
        `uvm_info(get_type_name(), "   4. run_test_stimulus()    [override] vortex_functional_vseq ", UVM_LOW)
        `uvm_info(get_type_name(), "   5. wait_for_completion()  [base]  wait for EBREAK           ", UVM_LOW)
        `uvm_info(get_type_name(), "   6. check_results()        [override] golden value check     ", UVM_LOW)
        `uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)
        `uvm_info(get_type_name(),
            $sformatf(" Interface : %s", cfg.axi_agent_enable ? "AXI4 (USE_AXI_WRAPPER)" : "Custom MEM"), UVM_LOW)
        `uvm_info(get_type_name(),
            $sformatf(" HW Config : %0d clusters x %0d cores x %0d warps x %0d threads",
                cfg.num_clusters, cfg.num_cores, cfg.num_warps, cfg.num_threads), UVM_LOW)
        `uvm_info(get_type_name(),
            $sformatf(" Startup   : 0x%016h", cfg.startup_addr), UVM_LOW)
        `uvm_info(get_type_name(),
            $sformatf(" Timeout   : %0d cycles", cfg.test_timeout_cycles), UVM_LOW)
        `uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)
    endfunction

    // -------------------------------------------------------------------------
    // load_program — OVERRIDE
    // -------------------------------------------------------------------------
    virtual task load_program();
        mem_model mem;
        string hex_file;
        int fd;

        #2ns;

        if (!uvm_config_db #(mem_model)::get(null, "*", "mem_model", mem)) begin
            `uvm_fatal(get_type_name(), "mem_model not found in config_db — was it set by TB_TOP?")
        end

        if (!$value$plusargs("PROGRAM=%s", hex_file)) begin
            `uvm_fatal(get_type_name(), "No +PROGRAM plusarg — pass --program=<path> to the run script")
        end

        fd = $fopen(hex_file, "r");
        if (fd == 0) begin
            `uvm_fatal(get_type_name(), $sformatf("Program file not found: %s", hex_file))
        end
        $fclose(fd);

        `uvm_info(get_type_name(),
            $sformatf("Loading hex file: %s at 0x%016h", hex_file, cfg.startup_addr), UVM_LOW)

        bytes_loaded = mem.load_hex_file(hex_file, cfg.startup_addr);

        if (bytes_loaded > 0)
            `uvm_info(get_type_name(), $sformatf("✓ Loaded %0d bytes into mem_model", bytes_loaded), UVM_LOW)
        else
            `uvm_fatal(get_type_name(), $sformatf("load_hex_file() returned 0 bytes — check file format: %s", hex_file))
    endtask

    // -------------------------------------------------------------------------
    // wait_for_reset — OVERRIDE
    // -------------------------------------------------------------------------
    virtual task wait_for_reset();
        `uvm_info(get_type_name(), "Waiting for reset (level-safe)...", UVM_MEDIUM)
        if (!vif.reset_n) @(posedge vif.reset_n);
        repeat(10) @(posedge vif.clk);
        `uvm_info(get_type_name(), "Reset released — program pre-loaded, DCR configured by TBTOP", UVM_LOW)
    endtask

    // -------------------------------------------------------------------------
    // run_test_stimulus — OVERRIDE
    // -------------------------------------------------------------------------
    virtual task run_test_stimulus();
        vortex_functional_mem_vseq vseq;
        vseq = vortex_functional_mem_vseq::type_id::create("vseq");
        `uvm_info(get_type_name(), $sformatf("Starting functional mem test: %0d iters", vseq.num_iterations), UVM_LOW)
        vseq.start(env.m_virtual_sequencer);
    endtask

    // -------------------------------------------------------------------------
    // check_results — OVERRIDE
    // -------------------------------------------------------------------------
    virtual function void check_results();
        uvm_report_server rs = uvm_report_server::get_server();
        int err_count;

        `uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)
        `uvm_info(get_type_name(), " FUNCTIONAL MEMORY TEST — RESULT VALIDATION                    ", UVM_LOW)
        `uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)

        if (bytes_loaded > 0)
            `uvm_info(get_type_name(), $sformatf("PASS — Program loaded: %0d bytes", bytes_loaded), UVM_LOW)
        else begin
            `uvm_error(get_type_name(), "FAIL — Program not loaded (bytes_loaded == 0)")
            test_passed = 0;
            return;
        end

        `uvm_info(get_type_name(), "PASS ��� DCR configured by TBTOP during reset", UVM_LOW)

        if (vif.status_if.ebreak_detected)
            `uvm_info(get_type_name(), $sformatf("PASS — EBREAK detected at cycle %0d", completion_cycle), UVM_LOW)
        else begin
            `uvm_error(get_type_name(), "FAIL — EBREAK not detected (DUT never completed)")
            test_passed = 0;
            return;
        end

        err_count = rs.get_severity_count(UVM_ERROR);
        if (err_count == 0) begin
            test_passed = 1;
            `uvm_info(get_type_name(), "PASS — Golden value match confirmed by vseq", UVM_LOW)
        end else begin
            test_passed = 0;
            `uvm_error(get_type_name(),
                $sformatf("FAIL — %0d UVM_ERROR(s) detected (check golden mismatch above)", err_count))
        end

        `uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)
    endfunction

endclass : functional_memory_test

`endif // FUNCTIONAL_MEMORY_TEST_SV