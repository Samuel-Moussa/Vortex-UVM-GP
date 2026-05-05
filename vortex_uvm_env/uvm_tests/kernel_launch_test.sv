////////////////////////////////////////////////////////////////////////////////
// File: kernel_launch_test.sv
// Description: Kernel Launch Test
//
// Purpose:
//   Verifies that the host path can preload a Vortex kernel binary, launch it
//   through the host agent, and compare a result window against SimX.
//
// This test defaults to the vecadd kernel binary and its destination buffer,
// but callers can override the program path and result region via plusargs.
////////////////////////////////////////////////////////////////////////////////

`ifndef KERNEL_LAUNCH_TEST_SV
`define KERNEL_LAUNCH_TEST_SV

class kernel_launch_test extends vortex_base_test;
	`uvm_component_utils(kernel_launch_test)

	function new(string name = "kernel_launch_test", uvm_component parent = null);
		super.new(name, parent);
	endfunction

	virtual function void customize_config();
		string default_program_path;
		bit compare_results;
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
			default_program_path = "../Vortex/tests/kernel/vecadd/vecadd.bin";
			cfg.program_path = default_program_path;
		end

		compare_results = 0;
		if (cfg.program_path.len() >= 10) begin
			if (cfg.program_path.substr(cfg.program_path.len()-10, cfg.program_path.len()-1) == "vecadd.bin") begin
				compare_results = 1;
			end else if (cfg.program_path.substr(cfg.program_path.len()-10, cfg.program_path.len()-1) == "vecadd.elf") begin
				compare_results = 1;
			end
		end

		result_base_override_set = $value$plusargs("RESULT_BASE_ADDR=%h", result_base_override);
		result_size_override_set = $value$plusargs("RESULT_SIZE_BYTES=%d", result_size_override);

		if (result_base_override_set)
			cfg.result_base_addr = result_base_override;
		else if (compare_results)
			cfg.result_base_addr = 64'h80007D88;
		else
			cfg.result_base_addr = 64'h0;

		if (result_size_override_set)
			cfg.result_size_bytes = result_size_override;
		else if (compare_results)
			cfg.result_size_bytes = 64;
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

		if (cfg.result_size_bytes > 0) begin
			if (env.m_scoreboard.num_comparisons == 0) begin
				`uvm_error(get_type_name(), "FAIL — scoreboard performed no result comparisons")
				test_passed = 0;
				return;
			end

			if (env.m_scoreboard.num_failed != 0) begin
				`uvm_error(get_type_name(),
					$sformatf("FAIL — scoreboard reported %0d failed comparison(s)", env.m_scoreboard.num_failed))
				test_passed = 0;
				return;
			end
		end else begin
			`uvm_info(get_type_name(), "INFO — result comparisons disabled for this program", UVM_LOW)
		end

		if (err_count == 0) begin
			test_passed = 1;
			`uvm_info(get_type_name(),
				$sformatf("PASS — kernel launch and result comparison succeeded (%0d comparisons, %0d passed)",
					env.m_scoreboard.num_comparisons,
					env.m_scoreboard.num_passed),
				UVM_LOW)
		end else begin
			test_passed = 0;
			`uvm_error(get_type_name(),
				$sformatf("FAIL — %0d UVM_ERROR(s) detected during kernel launch test", err_count))
		end

		`uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)
	endfunction

endclass : kernel_launch_test

`endif // KERNEL_LAUNCH_TEST_SV
