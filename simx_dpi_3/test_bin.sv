////////////////////////////////////////////////////////////////////////////////
// test_bin.sv - Binary File Test (Post-Mortem Mode, FIXED DCR)
// 
// This test loads a .bin kernel file and runs SimX to completion.
// Usage: +BIN=<path_to_kernel.bin> [+LOAD_ADDR=<hex_address>]
////////////////////////////////////////////////////////////////////////////////

module test_bin;

    // DPI Imports
    import "DPI-C" context function int simx_init(int nc, int nw, int nt);
    import "DPI-C" context function int simx_load_bin(string filepath, longint load_addr);
    import "DPI-C" context function void simx_read_mem(longint addr, int size, inout byte data[]);
    import "DPI-C" context function int simx_run();
    import "DPI-C" context function void simx_dcr_write(int addr, int value);
    import "DPI-C" context function void simx_cleanup();

    // Configuration parameters
    int num_cores = 2;
    int num_warps = 4;
    int num_threads = 4;
    longint startup_addr = 64'h80000000;
    longint result_addr = 64'h80100000;
    int result_size = 1024;
    
    // CORRECTED DCR addresses
    int dcr_startup_addr0 = 32'h001;  // VX_DCR_BASE_STARTUP_ADDR0
    int dcr_startup_addr1 = 32'h002;  // VX_DCR_BASE_STARTUP_ADDR1
    
    bit dump_waves = 1;
    
    // Binary file path
    string bin_file;
    longint load_addr;
    
    // Test control
    int exitcode;
    byte result_buffer[];

    initial begin
        $display("================================================================================");
        $display("  SimX Binary File Test (Post-Mortem Mode, FIXED DCR)");
        $display("================================================================================");

        // Get binary file from command line
        if (!$value$plusargs("BIN=%s", bin_file)) begin
            $error("[TEST] No binary file specified! Use +BIN=<filename>");
            $finish(1);
        end
        
        $display("[TEST] Binary file: %s", bin_file);

        // Get configuration from plusargs
        void'($value$plusargs("CORES=%d", num_cores));
        void'($value$plusargs("WARPS=%d", num_warps));
        void'($value$plusargs("THREADS=%d", num_threads));
        void'($value$plusargs("STARTUP_ADDR=%h", startup_addr));
        void'($value$plusargs("RESULT_ADDR=%h", result_addr));
        void'($value$plusargs("RESULT_SIZE=%d", result_size));
        
        if ($test$plusargs("no_waves"))
            dump_waves = 0;
        
        // Get load address (default from startup_addr)
        if (!$value$plusargs("LOAD_ADDR=%h", load_addr)) begin
            load_addr = startup_addr;
        end
        
        $display("[TEST] Load address: 0x%h", load_addr);

        // Dump waves if requested
        if ($test$plusargs("dump_waves") || dump_waves) begin
            $dumpfile("simx_bin_test.vcd");
            $dumpvars(0, test_bin);
            $display("[TEST] Waveform dumping enabled");
        end

        // Print configuration
        $display("\n--- Configuration ---");
        $display("  Cores:        %0d", num_cores);
        $display("  Warps:        %0d", num_warps);
        $display("  Threads:      %0d", num_threads);
        $display("  Startup Addr: 0x%h", startup_addr);
        $display("  Load Addr:    0x%h", load_addr);
        $display("  Result Addr:  0x%h", result_addr);
        $display("  DCR Addr0:    0x%h (corrected)", dcr_startup_addr0);
        $display("  DCR Addr1:    0x%h (corrected)", dcr_startup_addr1);

        // 1. Initialize SimX
        $display("\n[TEST] Step 1: Initializing SimX...");
        if (simx_init(num_cores, num_warps, num_threads) != 0) begin
            $error("[TEST] SimX initialization failed!");
            $finish(1);
        end

        // 2. Configure DCRs
        $display("\n[TEST] Step 2: Configuring DCRs...");
        configure_dcrs();

        // 3. Load binary kernel
        $display("\n[TEST] Step 3: Loading kernel binary...");
        if (simx_load_bin(bin_file, load_addr) != 0) begin
            $error("[TEST] Failed to load kernel binary!");
            simx_cleanup();
            $finish(1);
        end
        $display("[TEST] Kernel loaded successfully");

        // 4. Run to completion
        $display("\n[TEST] Step 4: Running SimX to completion...");
        exitcode = simx_run();
        
        if (exitcode != 0) begin
            $error("[TEST] Execution failed with exit code: %0d", exitcode);
        end else begin
            $display("[TEST] Execution completed successfully");
        end

        // 5. Check results
        $display("\n[TEST] Step 5: Verifying results...");
        check_results(result_addr, result_size);

        // 6. Cleanup
        #100;
        simx_cleanup();
        
        $display("\n================================================================================");
        $display("  Test %s (exit code: %0d)", (exitcode == 0) ? "PASSED" : "FAILED", exitcode);
        $display("================================================================================");
        $finish(exitcode);
    end

    // Task: Configure Device Configuration Registers
    task configure_dcrs();
        // CORRECTED: Use actual DCR addresses
        $display("[TEST] Writing DCR 0x%h = 0x%h", dcr_startup_addr0, startup_addr[31:0]);
        simx_dcr_write(dcr_startup_addr0, startup_addr[31:0]);
        
        if (startup_addr[63:32] != 32'h0) begin
            $display("[TEST] Writing DCR 0x%h = 0x%h", dcr_startup_addr1, startup_addr[63:32]);
            simx_dcr_write(dcr_startup_addr1, startup_addr[63:32]);
        end
        
        $display("[TEST] DCR configuration complete");
    endtask

    // Task: Verify results
    task check_results(longint addr, int size);
        result_buffer = new[size];
        simx_read_mem(addr, size, result_buffer);
        
        $display("[TEST] Read %0d bytes from result area at 0x%h", size, addr);
        
        // Display first few bytes for debugging
        $write("[TEST] First 16 bytes: ");
        for (int i = 0; i < 16 && i < size; i++) begin
            $write("%02x ", result_buffer[i]);
        end
        $display("");
        
        // Add specific result verification logic here
        // Example: Compare against golden values, check magic numbers, etc.
    endtask

endmodule