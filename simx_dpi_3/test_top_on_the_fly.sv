////////////////////////////////////////////////////////////////////////////////
// test_top_on_the_fly.sv - On-the-Fly Verification Test (FIXED DCR)
// 
// This test demonstrates on-the-fly verification where:
// 1. Program is loaded into SimX memory
// 2. SimX steps N cycles at a time
// 3. Results are checked periodically during execution
////////////////////////////////////////////////////////////////////////////////

module test_top_on_the_fly;

    // DPI Imports
    import "DPI-C" context function int simx_init(int nc, int nw, int nt);
    import "DPI-C" context function void simx_write_mem(longint addr, int size, input byte data[]);
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
    
    // Test control
    int step_size = 10;      // Cycles to step each iteration
    int max_cycles = 100000; // Maximum cycles before timeout
    int check_interval = 100; // Check results every N cycles
    int current_cycle;
    int step_result;
    bit dump_waves = 1;
    
    // Test data
    byte test_program[];
    byte result_buffer[];

    initial begin
        $display("================================================================================");
        $display("  SimX On-the-Fly Verification Test (FIXED DCR)");
        $display("================================================================================");

        // Get configuration from plusargs
        void'($value$plusargs("CORES=%d", num_cores));
        void'($value$plusargs("WARPS=%d", num_warps));
        void'($value$plusargs("THREADS=%d", num_threads));
        void'($value$plusargs("STARTUP_ADDR=%h", startup_addr));
        void'($value$plusargs("STEP_CYCLES=%d", step_size));
        void'($value$plusargs("TIMEOUT=%d", max_cycles));
        void'($value$plusargs("CHECK_INTERVAL=%d", check_interval));
        
        if ($test$plusargs("no_waves"))
            dump_waves = 0;

        current_cycle = 0;

        // Dump waves if requested
        if ($test$plusargs("dump_waves") || dump_waves) begin
            $dumpfile("simx_onthefly.vcd");
            $dumpvars(0, test_top_on_the_fly);
            $display("[TEST] Waveform dumping enabled");
        end

        // Print configuration
        $display("\n--- Configuration ---");
        $display("  Cores:          %0d", num_cores);
        $display("  Warps:          %0d", num_warps);
        $display("  Threads:        %0d", num_threads);
        $display("  Startup Addr:   0x%h", startup_addr);
        $display("  DCR Addr0:      0x%h (corrected)", dcr_startup_addr0);
        $display("  DCR Addr1:      0x%h (corrected)", dcr_startup_addr1);
        $display("  Step Size:      %0d cycles", step_size);
        $display("  Check Interval: %0d cycles", check_interval);
        $display("  Max Cycles:     %0d", max_cycles);

        // 1. Initialize SimX
        $display("\n[TEST] Step 1: Initializing SimX...");
        if (simx_init(num_cores, num_warps, num_threads) != 0) begin
            $error("[TEST] SimX initialization failed!");
            $finish(1);
        end

        // 2. Configure DCRs
        $display("\n[TEST] Step 2: Configuring DCRs...");
        configure_dcrs();

        // 3. Load program
        $display("\n[TEST] Step 3: Loading program...");
        load_test_program(startup_addr);

        // 4. Run in stepped fashion (ON-THE-FLY MODE)
        $display("\n[TEST] Step 4: Running SimX in stepped mode...");
        
        while (current_cycle < max_cycles) begin
            // Step N cycles
            step_result = simx_step(step_size);
            current_cycle += step_size;
            
            // Periodic status
            if (current_cycle % 1000 == 0) begin
                $display("[TEST] Cycle %0d / %0d", current_cycle, max_cycles);
            end
            
            // Optional: Check intermediate results every K cycles
            if (current_cycle % check_interval == 0) begin
                check_intermediate_results(result_addr);
            end
            
            // Check if execution completed
            if (step_result != 0) begin
                $display("[TEST] SimX signaled completion at cycle %0d", current_cycle);
                break;
            end
            
            // Small delay for simulation timing
            #1;
        end

        if (current_cycle >= max_cycles) begin
            $warning("[TEST] Reached maximum cycles (%0d) without completion", max_cycles);
        end

        // 5. Final result check
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

    // Task: Load test program
    task load_test_program(longint load_addr);
        test_program = new[16];
        test_program = '{
            8'h13, 8'h00, 8'h00, 8'h00,  // nop
            8'h13, 8'h00, 8'h00, 8'h00,  // nop
            8'h13, 8'h00, 8'h00, 8'h00,  // nop
            8'h73, 8'h00, 8'h10, 8'h00   // ebreak (exit)
        };
        
        simx_write_mem(load_addr, test_program.size(), test_program);
        $display("[TEST] Loaded %0d bytes at 0x%h", test_program.size(), load_addr);
    endtask

    // Task: Check intermediate results during execution
    task check_intermediate_results(longint addr);
        byte temp_buffer[];
        temp_buffer = new[64]; // Read small amount
        
        simx_read_mem(addr, 64, temp_buffer);
        
        // Add your intermediate checking logic here
        // This could compare against RTL memory or check invariants
    endtask

    // Task: Final verification
    task check_final_results(longint addr, int size);
        result_buffer = new[size];
        simx_read_mem(addr, size, result_buffer);
        
        $display("[TEST] Final check: Read %0d bytes from 0x%h", size, addr);
        
        // Display first few bytes
        $write("[TEST] First 16 bytes: ");
        for (int i = 0; i < 16 && i < size; i++) begin
            $write("%02x ", result_buffer[i]);
        end
        $display("");
        
        // Add your verification logic
        // Compare against expected results or RTL memory
    endtask

endmodule