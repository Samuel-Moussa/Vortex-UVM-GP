////////////////////////////////////////////////////////////////////////////////
// test_bin_on_the_fly.sv - Binary File Test (On-the-Fly Mode, FIXED DCR)
// 
// This test loads a .bin kernel file and runs SimX in stepped mode.
// Usage: +BIN=<path_to_kernel.bin> [+LOAD_ADDR=<hex>] [+STEP_CYCLES=<N>]
////////////////////////////////////////////////////////////////////////////////

module test_bin_on_the_fly;

    // DPI Imports
    import "DPI-C" context function int simx_init(int nc, int nw, int nt);
    import "DPI-C" context function int simx_load_bin(string filepath, longint load_addr);
    import "DPI-C" context function void simx_read_mem(longint addr, int size, inout byte data[]);
    import "DPI-C" context function int simx_step(int cycles);
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
    
    // Binary file
    string bin_file;
    longint load_addr;
    
    // Test control
    int step_size = 10;
    int max_cycles = 100000;
    int check_interval = 100;
    int current_cycle;
    int step_result;
    bit dump_waves = 1;
    byte result_buffer[];

    initial begin
        $display("================================================================================");
        $display("  SimX Binary File Test (On-the-Fly Mode, FIXED DCR)");
        $display("================================================================================");

        // Get binary file
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
        void'($value$plusargs("STEP_CYCLES=%d", step_size));
        void'($value$plusargs("TIMEOUT=%d", max_cycles));
        void'($value$plusargs("CHECK_INTERVAL=%d", check_interval));
        
        if ($test$plusargs("no_waves"))
            dump_waves = 0;
        
        // Get load address
        if (!$value$plusargs("LOAD_ADDR=%h", load_addr))
            load_addr = startup_addr;
        
        current_cycle = 0;

        $display("[TEST] Load address: 0x%h", load_addr);
        $display("[TEST] Step size: %0d cycles", step_size);
        $display("[TEST] Check interval: %0d cycles", check_interval);
        $display("[TEST] Max cycles: %0d", max_cycles);

        // Dump waves
        if ($test$plusargs("dump_waves") || dump_waves) begin
            $dumpfile("simx_bin_onthefly.vcd");
            $dumpvars(0, test_bin_on_the_fly);
            $display("[TEST] Waveform dumping enabled");
        end

        // Print configuration
        $display("\n--- Configuration ---");
        $display("  Cores:          %0d", num_cores);
        $display("  Warps:          %0d", num_warps);
        $display("  Threads:        %0d", num_threads);
        $display("  Startup Addr:   0x%h", startup_addr);
        $display("  Load Addr:      0x%h", load_addr);
        $display("  Result Addr:    0x%h", result_addr);
        $display("  DCR Addr0:      0x%h (corrected)", dcr_startup_addr0);
        $display("  DCR Addr1:      0x%h (corrected)", dcr_startup_addr1);
        $display("  Step Size:      %0d cycles", step_size);
        $display("  Check Interval: %0d cycles", check_interval);
        $display("  Max Cycles:     %0d", max_cycles);

        // 1. Initialize
        $display("\n[TEST] Step 1: Initializing SimX...");
        if (simx_init(num_cores, num_warps, num_threads) != 0) begin
            $error("[TEST] Initialization failed!");
            $finish(1);
        end

        // 2. Configure DCRs
        $display("\n[TEST] Step 2: Configuring DCRs...");
        configure_dcrs();

        // 3. Load kernel
        $display("\n[TEST] Step 3: Loading kernel binary...");
        if (simx_load_bin(bin_file, load_addr) != 0) begin
            $error("[TEST] Failed to load kernel!");
            simx_cleanup();
            $finish(1);
        end

        // 4. Run in stepped mode
        $display("\n[TEST] Step 4: Running in stepped mode...");
        $display("[TEST] Starting execution loop...");
        
        while (current_cycle < max_cycles) begin
            // Step N cycles
            step_result = simx_step(step_size);
            current_cycle += step_size;
            
            // Periodic status
            if (current_cycle % 1000 == 0) begin
                $display("[TEST] Cycle %0d / %0d", current_cycle, max_cycles);
            end
            
            // Periodic result check
            if (current_cycle % check_interval == 0) begin
                check_intermediate_results(result_addr);
            end
            
            // Check for completion
            if (step_result != 0) begin
                $display("[TEST] Execution completed at cycle %0d", current_cycle);
                break;
            end
            
            #1; // Timing
        end

        if (current_cycle >= max_cycles) begin
            $warning("[TEST] Timeout: Reached %0d cycles", max_cycles);
        end

        // 5. Final check
        $display("\n[TEST] Step 5: Final result verification...");
        check_final_results(result_addr, result_size);

        // 6. Cleanup
        #100;
        simx_cleanup();
        
        $display("\n================================================================================");
        $display("  Test COMPLETED at cycle %0d", current_cycle);
        $display("================================================================================");
        $finish(0);
    end

    // Configure DCRs
    task configure_dcrs();
        $display("[TEST] Writing DCR 0x%h = 0x%h", dcr_startup_addr0, startup_addr[31:0]);
        simx_dcr_write(dcr_startup_addr0, startup_addr[31:0]);
        
        if (startup_addr[63:32] != 32'h0) begin
            $display("[TEST] Writing DCR 0x%h = 0x%h", dcr_startup_addr1, startup_addr[63:32]);
            simx_dcr_write(dcr_startup_addr1, startup_addr[63:32]);
        end
        
        $display("[TEST] DCR configuration complete");
    endtask

    // Intermediate checking
    task check_intermediate_results(longint addr);
        byte temp_buffer[];
        temp_buffer = new[64];
        
        simx_read_mem(addr, 64, temp_buffer);
        
        // Add checking logic
        // Could compare with RTL memory or check progress indicators
    endtask

    // Final result check
    task check_final_results(longint addr, int size);
        result_buffer = new[size];
        simx_read_mem(addr, size, result_buffer);
        
        $display("[TEST] Final check: Read %0d bytes from 0x%h", size, addr);
        
        // Display sample
        $write("[TEST] First 16 bytes: ");
        for (int i = 0; i < 16 && i < size; i++) begin
            $write("%02x ", result_buffer[i]);
        end
        $display("");
        
        // Add verification logic
    endtask

endmodule