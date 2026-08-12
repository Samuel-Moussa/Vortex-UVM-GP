////////////////////////////////////////////////////////////////////////////////
// File: kernel_launch_test.svh
// Description: Kernel Launch Test
//
// Purpose:
//   Verifies that the host path can preload a Vortex kernel binary, launch it
//   through the host agent, and check completion plus any configured result
//   window against SimX.
//
// This test defaults to the vecadd kernel binary and its destination buffer,
// but callers can override the program path and result region via plusargs.
// Kernels such as fibonacci may complete without enabling result comparisons,
// while heavier programs such as conform may require a longer timeout.
////////////////////////////////////////////////////////////////////////////////

`ifndef KERNEL_LAUNCH_TEST_SV
`define KERNEL_LAUNCH_TEST_SV

class kernel_launch_test extends vortex_base_test;
	`uvm_component_utils(kernel_launch_test)

	// Set when this program has no end-state check (no result region, no console
	// output) but lockstep is armed: the non-vacuity verdict moves to check_phase,
	// where the lockstep tallies are final. See check_results()/check_phase().
	bit lockstep_vacuity_deferred;

	function new(string name = "kernel_launch_test", uvm_component parent = null);
		super.new(name, parent);
		lockstep_vacuity_deferred = 0;
	endfunction

	virtual function void customize_config();
		string default_program_path;
		bit result_base_override_set;
		bit result_size_override_set;
		bit [63:0] result_base_override;
		int unsigned result_size_override;

		cfg.enable_scoreboard    = 1;
		cfg.enable_coverage      = 1;
		cfg.simx_enable          = 1;
		cfg.simx_path            = "DPI_MODE";
		cfg.dcr_agent_is_active  = 1;
		cfg.host_agent_enable    = 1;
		cfg.host_agent_is_active = 1;
		cfg.axi_agent_is_active  = cfg.axi_agent_enable;

		if (cfg.program_path == "") begin
			default_program_path = "../Vortex/tests/kernel/vecadd/vecadd.elf";
			cfg.program_path = default_program_path;
		end

		// Detect heavy "conform" test and increase timeout accordingly. Conform
		// is a suite of mixed subtests and may take much longer to complete.
		if (cfg.program_path.len() >= 11) begin
			if (cfg.program_path.substr(cfg.program_path.len()-11, cfg.program_path.len()-1) == "conform.bin") begin
				cfg.test_timeout_cycles = cfg.global_timeout_cycles;
				`uvm_info(get_type_name(), $sformatf("Conform detected: extending timeout to %0d cycles", cfg.test_timeout_cycles), UVM_LOW)
			end else if (cfg.program_path.substr(cfg.program_path.len()-11, cfg.program_path.len()-1) == "conform.elf") begin
				cfg.test_timeout_cycles = cfg.global_timeout_cycles;
				`uvm_info(get_type_name(), $sformatf("Conform detected: extending timeout to %0d cycles", cfg.test_timeout_cycles), UVM_LOW)
			end else if (cfg.program_path.substr(cfg.program_path.len()-11, cfg.program_path.len()-1) == "conform.hex") begin
				cfg.test_timeout_cycles = cfg.global_timeout_cycles;
				`uvm_info(get_type_name(), $sformatf("Conform detected: extending timeout to %0d cycles", cfg.test_timeout_cycles), UVM_LOW)
			end
		end

		result_base_override_set = $value$plusargs("RESULT_BASE_ADDR=%h", result_base_override);
		result_size_override_set = $value$plusargs("RESULT_SIZE_BYTES=%d", result_size_override);

		if (result_base_override_set)
			cfg.result_base_addr = result_base_override;
		else
			cfg.result_base_addr = 64'h0;

		if (result_size_override_set)
			cfg.result_size_bytes = result_size_override;
		else
			cfg.result_size_bytes = 0;

		if (cfg.test_timeout_cycles > cfg.global_timeout_cycles)
			cfg.test_timeout_cycles = cfg.global_timeout_cycles;

		`uvm_info(get_type_name(),
			$sformatf("Kernel launch cfg: startup=0x%016h result=0x%016h size=%0d timeout=%0d cycles iface=%s program=%s",
				cfg.startup_addr,
				cfg.result_base_addr,
				cfg.result_size_bytes,
				cfg.test_timeout_cycles,
				cfg.axi_agent_enable ? "AXI4" : "CustomMEM",
				cfg.program_path), UVM_LOW)
	endfunction

	virtual function void end_of_elaboration_phase(uvm_phase phase);
		super.end_of_elaboration_phase(phase);
		`uvm_info(get_type_name(), {"\n",
			"----------------------------------------------------------------\n",
			" KERNEL LAUNCH TEST                                            \n",
			"----------------------------------------------------------------\n",
			"  Test Flow:                                                   \n",
			"    1. preload kernel binary into mem_model                    \n",
			"    2. wait for reset release                                  \n",
			"    3. launch kernel through host agent                       \n",
			"    4. wait for completion                                     \n",
			"    5. compare result window against SimX                      \n",
			$sformatf("  Startup   : 0x%016h\n", cfg.startup_addr),
			$sformatf("  Result    : 0x%016h (%0d bytes)\n", cfg.result_base_addr, cfg.result_size_bytes),
			$sformatf("  Timeout   : %0d cycles\n", cfg.test_timeout_cycles),
			"----------------------------------------------------------------"
		}, UVM_LOW)
	endfunction

	virtual task load_program();
		mem_model mem;
		string kernel_path;
		string file_ext;
		int fd;
		bit is_hex;

		#2ns;

		if (!uvm_config_db#(mem_model)::get(null, "*", "mem_model", mem)) begin
			`uvm_fatal(get_type_name(), "mem_model not found in config_db — was it set by TB_TOP?")
		end

		kernel_path = cfg.program_path;
		if (kernel_path == "") begin
			`uvm_fatal(get_type_name(), "No program path configured — pass +PROGRAM or set the default kernel path")
		end

		fd = $fopen(kernel_path, "r");
		if (fd == 0) begin
			`uvm_fatal(get_type_name(), $sformatf("Kernel program not found: %s", kernel_path))
		end
		$fclose(fd);

		// Detect file format from extension
		if (kernel_path.len() > 4) begin
			file_ext = kernel_path.substr(kernel_path.len()-4, kernel_path.len()-1);
			is_hex   = (file_ext == ".hex");
		end else begin
			is_hex = 0;
		end

		`uvm_info(get_type_name(),
			$sformatf("Loading kernel program: %s (%s format) at 0x%016h",
				kernel_path, is_hex ? "HEX" : "BIN", cfg.startup_addr),
			UVM_LOW)

		if (is_hex) begin
			bytes_loaded = mem.load_hex_file(kernel_path, cfg.startup_addr);
		end else begin
			bytes_loaded = mem.load_binary_file(kernel_path, cfg.startup_addr);
		end

		if (bytes_loaded > 0) begin
			`uvm_info(get_type_name(), $sformatf("✓ Loaded %0d bytes into mem_model", bytes_loaded), UVM_LOW)
		end else begin
			`uvm_fatal(get_type_name(),
				$sformatf("load_%s_file() returned %0d bytes — check kernel program: %s",
					is_hex ? "hex" : "binary", bytes_loaded, kernel_path))
		end
	endtask

	virtual task run_test_stimulus();
		kernel_launch_vseq vseq;

		if (env == null || env.m_virtual_sequencer == null) begin
			`uvm_fatal(get_type_name(), "Virtual sequencer is null")
		end

		vseq = kernel_launch_vseq::type_id::create("vseq");
		vseq.cfg                = cfg;

		`uvm_info(get_type_name(),
			$sformatf("Executing kernel launch virtual sequence at 0x%016h (cores=%0d warps=%0d threads=%0d timeout=%0d)",
				cfg.startup_addr,
				cfg.num_cores,
				cfg.num_warps,
				cfg.num_threads,
				cfg.test_timeout_cycles),
			UVM_LOW)

		vseq.start(env.m_virtual_sequencer);
	endtask

	virtual function void check_results();
		uvm_report_server rs;
		int err_count;
		int launch_count;
		int completion_count;

		rs = uvm_report_server::get_server();
		err_count = rs.get_severity_count(UVM_ERROR);

		launch_count = (env != null && env.m_host_agent != null && env.m_host_agent.m_monitor != null)
			? env.m_host_agent.m_monitor.num_kernel_launches
			: -1;
		completion_count = (env != null && env.m_host_agent != null && env.m_host_agent.m_monitor != null)
			? env.m_host_agent.m_monitor.num_kernel_completions
			: -1;

		`uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)
		`uvm_info(get_type_name(), " KERNEL LAUNCH TEST — RESULT VALIDATION                        ", UVM_LOW)
		`uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)

		if (bytes_loaded <= 0) begin
			`uvm_error(get_type_name(), "FAIL — kernel binary was not loaded")
			test_passed = 0;
			return;
		end

		if (!vif.status_if.ebreak_detected) begin
			`uvm_error(get_type_name(), "FAIL — kernel did not reach EBREAK/completion")
			test_passed = 0;
			return;
		end

		if (launch_count != 1) begin
			`uvm_error(get_type_name(), $sformatf("FAIL — expected exactly 1 kernel launch, saw %0d", launch_count))
			test_passed = 0;
			return;
		end

		if (completion_count != 1) begin
			`uvm_error(get_type_name(), $sformatf("FAIL — expected exactly 1 kernel completion, saw %0d", completion_count))
			test_passed = 0;
			return;
		end

		if (env == null || env.m_scoreboard == null) begin
			`uvm_error(get_type_name(), "FAIL — scoreboard is not available")
			test_passed = 0;
			return;
		end

		// A program passes only if SOME real check ran (memory or console).
		//
		// PHASE-ORDERING CAVEAT: this runs in run_phase, but two checkers deliberately
		// complete LATER, so their counters are legitimately 0 here:
		//   (a) with +LOCKSTEP_LOADFEED the end-state MEM compare is deferred to the
		//       scoreboard's report_phase so it runs against POST-FEED SimX
		//       (vortex_scoreboard.sv `endstate_feed_mode`); and
		//   (b) the per-instruction lockstep compares in its check_phase.
		// Failing here would be a FALSE "nothing was verified" verdict. So when either
		// deferred checker is armed, defer the non-vacuity verdict to this test's
		// report_phase (a UVM phase barrier guarantees both have finished by then).
		// Non-vacuity is preserved, not weakened: the deferred check still FAILS if
		// nothing actually compared anything.
		if (env.m_scoreboard.num_comparisons == 0 &&
		    env.m_scoreboard.num_console_checks == 0) begin
			if (cfg != null && cfg.enable_lockstep) begin
				lockstep_vacuity_deferred = 1;
				`uvm_info(get_type_name(),
					"No end-state check counted yet (deferred end-state compare and/or lockstep still pending) — deferring the non-vacuity verdict to report_phase",
					UVM_LOW)
			end else begin
				`uvm_error(get_type_name(),
					"FAIL — no functional verification performed (no memory or console comparison, and lockstep is disabled)")
				test_passed = 0;
				return;
			end
		end

		if ((env.m_scoreboard.num_mem_failed + env.m_scoreboard.num_console_failed) != 0) begin
			`uvm_error(get_type_name(),
				$sformatf("FAIL — scoreboard reported %0d failed check(s) (%0d memory, %0d console)",
					env.m_scoreboard.num_mem_failed + env.m_scoreboard.num_console_failed,
					env.m_scoreboard.num_mem_failed,
					env.m_scoreboard.num_console_failed))
			test_passed = 0;
			return;
		end

		if (err_count == 0) begin
			test_passed = 1;
			`uvm_info(get_type_name(),
				$sformatf("PASS — verified against SimX (mem comparisons=%0d passed, console checks=%0d passed)%s",
					env.m_scoreboard.num_comparisons,
					env.m_scoreboard.num_console_checks,
					lockstep_vacuity_deferred ? " [non-vacuity pending: lockstep check_phase]" : ""),
				UVM_LOW)
		end else begin
			test_passed = 0;
			`uvm_error(get_type_name(),
				$sformatf("FAIL — %0d UVM_ERROR(s) detected during kernel launch test", err_count))
		end

		`uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)
	endfunction

	//==========================================================================
	// report_phase — completes the DEFERRED non-vacuity verdict.
	//
	// Runs here (not check_phase) because BOTH deferred checkers must have finished:
	// the lockstep compares in check_phase, but the end-state MEM compare under
	// +LOCKSTEP_LOADFEED runs in vortex_scoreboard's report_phase (against post-feed
	// SimX). UVM function phases execute bottom-up, so the scoreboard — a deeper
	// component — has already produced its final counts when this executes.
	//
	// This is NOT a relaxation of Gate-0 non-vacuity: a run where NOTHING compared
	// anything still FAILS. It only stops a false "nothing was verified" verdict when
	// the real checks simply had not run yet at run_phase time. The error is emitted
	// BEFORE super.report_phase() so the base class's err_count/verdict includes it.
	//==========================================================================
	virtual function void report_phase(uvm_phase phase);
		int unsigned endstate_checks;
		int unsigned lockstep_pairs;

		if (lockstep_vacuity_deferred) begin
			endstate_checks = (env != null && env.m_scoreboard != null)
				? (env.m_scoreboard.num_comparisons + env.m_scoreboard.num_console_checks) : 0;
			lockstep_pairs  = (env != null && env.m_lockstep_scoreboard != null)
				? env.m_lockstep_scoreboard.n_pairs : 0;

			if (endstate_checks == 0 && lockstep_pairs == 0) begin
				`uvm_error(get_type_name(),
					"FAIL — no functional verification performed (end-state compared 0 words/console checks AND lockstep compared 0 instructions)")
				test_passed = 0;
			end else begin
				`uvm_info(get_type_name(),
					$sformatf("Non-vacuity satisfied: end-state checks=%0d, lockstep instruction pairs=%0d (both vs SimX)",
						endstate_checks, lockstep_pairs),
					UVM_LOW)
			end
		end

		super.report_phase(phase);
	endfunction

endclass : kernel_launch_test

`endif // KERNEL_LAUNCH_TEST_SV
