////////////////////////////////////////////////////////////////////////////////
// test_top.sv - Post-Mortem Verification Test (FIXED DCR ADDRESSES)
// 
// This test demonstrates post-mortem verification where:
// 1. Program is loaded into SimX memory
// 2. SimX runs to completion
// 3. Results are checked after execution finishes
////////////////////////////////////////////////////////////////////////////////

module test_top;

    // DPI Imports
    import "DPI-C" context function int simx_init(int nc, int nw, int nt);
    import "DPI-C" context function void simx_write_mem(longint addr, int size, input byte data[]);
    import "DPI-C" context function void simx_read_mem(longint addr, int size, inout byte data[]);
    import "DPI-C" context function int simx_run();
    import "DPI-C" context function void simx_dcr_write(int addr, int value);
    import "DPI-C" context function void simx_cleanup();

    // Configuration parameters (from plusargs or defaults)
    int num_cores = 2;
    int num_warps = 4;
    int num_threads = 4;
    longint startup_addr = 64'h80000000;
    longint result_addr = 64'h80100000;
    int result_size = 1024;
    
    // CORRECTED DCR addresses based on actual Vortex VX_types.h
    int dcr_startup_addr0 = 32'h001;  // VX_DCR_BASE_STARTUP_ADDR0 = 0x001
    int dcr_startup_addr1 = 32'h002;  // VX_DCR_BASE_STARTUP_ADDR1 = 0x002
    
    bit dump_waves = 1;
    
    // Test data
    byte test_program[];
    byte result_buffer[];
    
    // Control
    int exitcode;

    initial begin
        $display("================================================================================");
        $display("  SimX Post-Mortem Verification Test (FIXED DCR)");
        $display("================================================================================");

        // Get configuration from plusargs
        void'($value$plusargs("CORES=%d", num_cores));
        void'($value$plusargs("WARPS=%d", num_warps));
        void'($value$plusargs("THREADS=%d", num_threads));
        void'($value$plusargs("STARTUP_ADDR=%h", startup_addr));
        
        if ($test$plusargs("no_waves"))
            dump_waves = 0;

        // Dump waves if requested
        if ($test$plusargs("dump_waves") || dump_waves) begin
            $dumpfile("simx_postmortem.vcd");
            $dumpvars(0, test_top);
            $display("[TEST] Waveform dumping enabled");
        end

        // Print configuration
        $display("\n--- Configuration ---");
        $display("  Cores:        %0d", num_cores);
        $display("  Warps:        %0d", num_warps);
        $display("  Threads:      %0d", num_threads);
        $display("  Startup Addr: 0x%h", startup_addr);
        $display("  Result Addr:  0x%h", result_addr);
        $display("  DCR Addr0:    0x%h (corrected)", dcr_startup_addr0);
        $display("  DCR Addr1:    0x%h (corrected)", dcr_startup_addr1);

        // 1. Initialize SimX
        $display("\n[TEST] Step 1: Initializing SimX...");
        if (simx_init(num_cores, num_warps, num_threads) != 0) begin
            $error("[TEST] SimX initialization failed!");
            $finish(1);
        end
        $display("[TEST] SimX initialized successfully");

        // 2. Configure DCRs (set startup address)
        $display("\n[TEST] Step 2: Configuring DCRs...");
        configure_dcrs();

        // 3. Load program into memory
        $display("\n[TEST] Step 3: Loading program into memory...");
        load_test_program(startup_addr);

        // 4. Run SimX to completion (POST-MORTEM MODE)
        $display("\n[TEST] Step 4: Running SimX to completion...");
        exitcode = simx_run();
        
        if (exitcode != 0) begin
            $error("[TEST] SimX execution failed with exit code: %0d", exitcode);
        end else begin
            $display("[TEST] SimX execution completed successfully");
        end

        // 5. Read and verify results
        $display("\n[TEST] Step 5: Checking results...");
        check_results(result_addr, result_size);

        // 6. Cleanup
        #100;
        simx_cleanup();
        
        $display("\n================================================================================");
        $display("  Test %s", (exitcode == 0) ? "PASSED" : "FAILED");
        $display("================================================================================");
        $finish(exitcode);
    end

    // Task: Configure Device Configuration Registers
    task configure_dcrs();
        // CORRECTED: Use actual DCR addresses from VX_types.h
        // VX_DCR_BASE_STARTUP_ADDR0 = 0x001 (lower 32 bits)
        // VX_DCR_BASE_STARTUP_ADDR1 = 0x002 (upper 32 bits)
        
        $display("[TEST] Writing DCR 0x%h = 0x%h (startup_addr lower 32 bits)", 
                 dcr_startup_addr0, startup_addr[31:0]);
        simx_dcr_write(dcr_startup_addr0, startup_addr[31:0]);
        
        // For 64-bit addresses, also write upper 32 bits
        if (startup_addr[63:32] != 32'h0) begin
            $display("[TEST] Writing DCR 0x%h = 0x%h (startup_addr upper 32 bits)", 
                     dcr_startup_addr1, startup_addr[63:32]);
            simx_dcr_write(dcr_startup_addr1, startup_addr[63:32]);
        end
        
        $display("[TEST] DCR configuration complete");
    endtask

    // Task: Load test program into SimX memory
    task load_test_program(longint load_addr);
        // Simple test program with proper exit
        // RISC-V instructions:
        //   addi x0, x0, 0  (NOP)
        //   addi x0, x0, 0  (NOP)  
        //   addi x0, x0, 0  (NOP)
        //   ebreak          (Exit/breakpoint - signals completion)
        test_program = new[16];
        test_program = '{
            8'h13, 8'h00, 8'h00, 8'h00,  // nop (addi x0, x0, 0)
            8'h13, 8'h00, 8'h00, 8'h00,  // nop
            8'h13, 8'h00, 8'h00, 8'h00,  // nop
            8'h73, 8'h00, 8'h10, 8'h00   // ebreak (exit)
        };
        
        simx_write_mem(load_addr, test_program.size(), test_program);
        $display("[TEST] Loaded %0d bytes at 0x%h", test_program.size(), load_addr);
    endtask

    // Task: Verify execution results
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
        
        // Add your specific result checking logic here
        // Example: Check for expected values
        /*
        if (result_buffer[0] == 8'hXX) begin
            $display("[TEST] Result verification PASSED");
        end else begin
            $error("[TEST] Result verification FAILED");
        end
        */
    endtask

endmodule