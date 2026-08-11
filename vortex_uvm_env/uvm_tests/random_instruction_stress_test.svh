////////////////////////////////////////////////////////////////////////////////
// File: tests/random_instruction_stress_test.sv
// Description: Random Instruction Stress Test
//
// Follows the exact same 4-override pattern as kernel_launch_test.sv:
//   customize_config()   → enable scoreboard/simx, set timeout, read
//                          +NUM_STRESS_ITER plusarg
//   load_program()       → identical to kernel_launch_test::load_program()
//                          (mem_model + .hex/.bin detection)
//   run_test_stimulus()  → create random_instr_stress_vseq, set cfg +
//                          num_iterations, start on env.m_virtual_sequencer
//   check_results()      → 3-gate: bytes_loaded / ebreak_detected / 0 errors
//
// Run via run_vortex_uvm_enhanced.sh:
//
//   # Single iteration (riscv-dv auto-generates the program):
//   ./scripts/run_vortex_uvm_enhanced.sh \
//       --test=random_instruction_stress_test \
//       --program=riscv_rand_instr_test \
//       --timeout=500000
//
//   # 5 back-to-back iterations:
//   ./scripts/run_vortex_uvm_enhanced.sh \
//       --test=random_instruction_stress_test \
//       --program=riscv_rand_instr_test \
//       --timeout=500000 \
//       --stress-iter=5
//
// Plusargs accepted (beyond vortex_base_test defaults):
//   +NUM_STRESS_ITER=<n>   back-to-back iterations (default: 1)
////////////////////////////////////////////////////////////////////////////////

`ifndef RANDOM_INSTRUCTION_STRESS_TEST_SV
`define RANDOM_INSTRUCTION_STRESS_TEST_SV

class random_instruction_stress_test extends vortex_base_test;
    `uvm_component_utils(random_instruction_stress_test)

    int unsigned num_stress_iterations;

    function new(string name = "random_instruction_stress_test",
                 uvm_component parent = null);
        super.new(name, parent);
        num_stress_iterations = 1;
    endfunction

    //==========================================================================
    // customize_config — called by vortex_base_test::build_phase()
    //==========================================================================
    virtual function void customize_config();

        // Enable scoreboard + SimX golden model
        cfg.enable_scoreboard  = 1;
        cfg.enable_coverage    = 1;
        cfg.simx_enable        = 1;
        cfg.simx_path          = "DPI_MODE";

        // Activate required agents (same flags as kernel_launch_test)
        cfg.dcr_agent_is_active  = 1;
        cfg.host_agent_enable    = 1;
        cfg.host_agent_is_active = 1;
        cfg.axi_agent_is_active  = cfg.axi_agent_enable;

        // Default program — run script resolves riscv_rand_instr_test to a
        // .hex via riscv-dv and passes it as +PROGRAM=<path.hex>.
        // cfg.apply_plusargs() already populated cfg.program_path if +PROGRAM
        // was given; only set the default when it is empty.
        if (cfg.program_path == "")
            cfg.program_path = "riscv_rand_instr_test";

        // 500k cycles per iteration — override via --timeout=N on run script
        if (cfg.test_timeout_cycles < 500_000)
            cfg.test_timeout_cycles = 500_000;

        // No memory result window — completion indicator is EBREAK only
        cfg.result_base_addr  = 64'h0;
        cfg.result_size_bytes = 0;

        // Iteration count from plusarg (+NUM_STRESS_ITER=N)
        void'($value$plusargs("NUM_STRESS_ITER=%0d", num_stress_iterations));
        if (num_stress_iterations == 0) num_stress_iterations = 1;

        `uvm_info(get_type_name(),
            $sformatf("Stress config: program=%s  timeout=%0d  iterations=%0d",
                       cfg.program_path,
                       cfg.test_timeout_cycles,
                       num_stress_iterations), UVM_LOW)

    endfunction

    //==========================================================================
    // end_of_elaboration_phase — banner
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        `uvm_info(get_type_name(), {"\n",
            "----------------------------------------------------------------\n",
            " RANDOM INSTRUCTION STRESS TEST                                \n",
            "----------------------------------------------------------------\n",
            " Test Flow:                                                     \n",
            "   1. Load riscv-dv random program into mem_model              \n",
            "   2. Wait for reset release                                   \n",
            "   3. Launch kernel via host agent  (N iterations)             \n",
            "   4. Wait for EBREAK on each iteration                        \n",
            "   5. Check: bytes_loaded / EBREAK detected / 0 UVM errors     \n",
            $sformatf(" Program    : %s\n",      cfg.program_path),
            $sformatf(" Startup    : 0x%016h\n", cfg.startup_addr),
            $sformatf(" Timeout    : %0d cycles/iter\n", cfg.test_timeout_cycles),
            $sformatf(" Iterations : %0d\n",     num_stress_iterations),
            "----------------------------------------------------------------"
        }, UVM_LOW)
    endfunction

    //==========================================================================
    // load_program — identical to kernel_launch_test::load_program()
    //==========================================================================
    virtual task load_program();
        mem_model mem;
        string    kernel_path;
        string    file_ext;
        int       fd;
        bit       is_hex;

        #2ns; // let TB_TOP finish config_db setup

        if (!uvm_config_db#(mem_model)::get(null, "*", "mem_model", mem))
            `uvm_fatal(get_type_name(),
                "mem_model not found in config_db — was it set by TB_TOP?")

        kernel_path = cfg.program_path;

        if (kernel_path == "" || kernel_path == "riscv_rand_instr_test")
            `uvm_fatal(get_type_name(),
                {"No resolved hex path. Pass +PROGRAM=<path.hex> or let ",
                 "run_vortex_uvm_enhanced.sh generate and convert the riscv-dv ELF."})

        fd = $fopen(kernel_path, "r");
        if (fd == 0)
            `uvm_fatal(get_type_name(),
                $sformatf("Program file not found: %s", kernel_path))
        $fclose(fd);

        // Detect .hex vs binary from extension
        if (kernel_path.len() > 4) begin
            file_ext = kernel_path.substr(kernel_path.len()-4, kernel_path.len()-1);
            is_hex   = (file_ext == ".hex");
        end else begin
            is_hex = 0;
        end

        `uvm_info(get_type_name(),
            $sformatf("Loading stress program: %s  (%s)  at 0x%016h",
                       kernel_path, is_hex ? "HEX" : "BIN", cfg.startup_addr),
            UVM_LOW)

        if (is_hex)
            bytes_loaded = mem.load_hex_file   (kernel_path, cfg.startup_addr);
        else
            bytes_loaded = mem.load_binary_file(kernel_path, cfg.startup_addr);

        if (bytes_loaded > 0)
            `uvm_info(get_type_name(),
                $sformatf("✓ Loaded %0d bytes into mem_model", bytes_loaded), UVM_LOW)
        else
            `uvm_fatal(get_type_name(),
                $sformatf("load_%s_file() returned 0 bytes — check program: %s",
                           is_hex ? "hex" : "binary", kernel_path))
    endtask

    //==========================================================================
    // run_test_stimulus
    //==========================================================================
    virtual task run_test_stimulus();
        random_instr_stress_vseq vseq;

        if (env == null || env.m_virtual_sequencer == null)
            `uvm_fatal(get_type_name(), "Virtual sequencer is null")

        vseq                = random_instr_stress_vseq::type_id::create("stress_vseq");
        vseq.cfg            = cfg;
        vseq.num_iterations = num_stress_iterations;

        `uvm_info(get_type_name(),
            $sformatf("Starting stress vseq: %0d iteration(s) at 0x%016h",
                       num_stress_iterations, cfg.startup_addr), UVM_LOW)

        vseq.start(env.m_virtual_sequencer);
    endtask

    //==========================================================================
    // check_results
    //==========================================================================
    virtual function void check_results();
        uvm_report_server rs;
        int err_count;

        rs        = uvm_report_server::get_server();
        err_count = rs.get_severity_count(UVM_ERROR);

        `uvm_info(get_type_name(),
            "----------------------------------------------------------------", UVM_LOW)
        `uvm_info(get_type_name(),
            " RANDOM INSTRUCTION STRESS TEST — RESULT VALIDATION", UVM_LOW)
        `uvm_info(get_type_name(),
            "----------------------------------------------------------------", UVM_LOW)

        // Gate 1: program was loaded
        if (bytes_loaded <= 0) begin
            `uvm_error(get_type_name(), "FAIL — stress program was not loaded into mem_model")
            test_passed = 0;
            return;
        end

        // Gate 2: DUT reached EBREAK on the final iteration
        if (!vif.status_if.ebreak_detected) begin
            `uvm_error(get_type_name(),
                "FAIL — DUT did not reach EBREAK on the last stress iteration")
            test_passed = 0;
            return;
        end

        // Gate 3: zero UVM errors
        if (err_count != 0) begin
            `uvm_error(get_type_name(),
                $sformatf("FAIL — %0d UVM_ERROR(s) during stress test", err_count))
            test_passed = 0;
            return;
        end

        test_passed = 1;
        `uvm_info(get_type_name(),
            $sformatf("PASS — %0d stress iteration(s) completed, 0 errors",
                       num_stress_iterations), UVM_LOW)
        `uvm_info(get_type_name(),
            "----------------------------------------------------------------", UVM_LOW)

    endfunction

endclass : random_instruction_stress_test

`endif // RANDOM_INSTRUCTION_STRESS_TEST_SV
