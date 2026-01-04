module test_top;
    import vortex_config_pkg::*;

    // DPI Imports
    import "DPI-C" context function int simx_init(int nc, int nw, int nt);
    import "DPI-C" context function void simx_write_mem(longint addr, int size, input byte data[]);
    import "DPI-C" context function void simx_cleanup();

    // Small fake program (4 RISC-V NOPs: 0x00000013)
    byte fake_program[16] = '{
        8'h13, 8'h00, 8'h00, 8'h00,
        8'h13, 8'h00, 8'h00, 8'h00,
        8'h13, 8'h00, 8'h00, 8'h00,
        8'h13, 8'h00, 8'h00, 8'h00
    };

    initial begin
        $display("--- Starting SimX DPI Connection Test ---");

        // 1. Initialize
        if (simx_init(1, 1, 4) == 0) begin
            $display("[SV] SimX Object created successfully.");
        end else begin
            $display("[SV] ERROR: SimX Init failed.");
            $finish;
        end

        // 2. Write Data to SimX Memory (No kernel.bin needed!)
        $display("[SV] Pushing fake program to SimX memory...");
        simx_write_mem(64'h80000000, 16, fake_program);

        // 3. Cleanup
        #100;
        simx_cleanup();
        $display("--- Test Completed Successfully ---");
        $finish;
    end
endmodule