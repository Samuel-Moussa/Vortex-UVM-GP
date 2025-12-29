////////////////////////////////////////////////////////////////////////////////
// File: vortex_dcr_if.sv
// Description: Device Configuration Register (DCR) interface with clocking blocks
//
// Protocol: Simple write-only configuration interface
//   - No handshaking (single-cycle writes)
//   - Configures Vortex runtime parameters
//
// DCR Registers:
//   - Startup address (boot PC)
//   - Number of cores/warps/threads
//   - Performance monitoring controls
//   - Argument pointers
//
// Clocking Blocks:
//   - master_cb:  For drivers (writes DCRs)
//   - monitor_cb: For passive monitoring
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_DCR_IF_SV
`define VORTEX_DCR_IF_SV

//`include "VX_define.vh"
import vortex_config_pkg::*;


interface vortex_dcr_if (
    input logic clk,
    input logic reset_n
);
    //==========================================================================
    // PARAMETERS
    //==========================================================================
    localparam ADDR_WIDTH = vortex_config_pkg::VX_MEM_ADDR_WIDTH;

    localparam DATA_WIDTH = vortex_config_pkg::VX_MEM_DATA_WIDTH;


    //==========================================================================
    // DCR WRITE SIGNALS
    //==========================================================================
    logic                    wr_valid;
    logic [ADDR_WIDTH-1:0]   wr_addr;
    logic [DATA_WIDTH-1:0]   wr_data;

    //==========================================================================
    // CLOCKING BLOCK: MASTER (For UVM Driver)
    //==========================================================================
    clocking master_cb @(posedge clk);
        default input #1step output #0;
        
        output  wr_valid;
        output  wr_addr;
        output  wr_data;
    endclocking

    //==========================================================================
    // CLOCKING BLOCK: MONITOR (For Passive Observation)
    //==========================================================================
    clocking monitor_cb @(posedge clk);
        default input #1step;
        
        input wr_valid;
        input wr_addr;
        input wr_data;
    endclocking

    //==========================================================================
    // MODPORTS
    //==========================================================================
    
    // For UVM driver
    modport master_driver (
        clocking master_cb,
        input clk, reset_n
    );
    
    // For UVM monitor
    modport monitor (
        clocking monitor_cb,
        input clk, reset_n
    );
    
    // For DUT connection
    modport dut (
        input  wr_valid,
        input  wr_addr,
        input  wr_data
    );

    //==========================================================================
    // HELPER FUNCTIONS
    //==========================================================================
    
    // Check if write is happening
    function automatic bit is_write();
        return wr_valid;
    endfunction
    
    // Decode DCR address to name
    function automatic string decode_dcr_addr(logic [ADDR_WIDTH-1:0] addr);
        // Based on VX_define.vh DCR addresses
        case (addr)
            VX_DCR_BASE_STARTUP_ADDR0:     return "STARTUP_ADDR0";
            VX_DCR_BASE_STARTUP_ADDR0 + 4: return "STARTUP_ADDR1";
            VX_DCR_BASE_STARTUP_ADDR0 + 8: return "NUM_CORES";
            VX_DCR_BASE_MPM_CLASS:         return "MPM_CLASS";
            default: return $sformatf("UNKNOWN_DCR[0x%h]", addr);
        endcase
    endfunction

    //==========================================================================
    // TASKS FOR TESTBENCH
    //==========================================================================
    
    // Task: Perform single DCR write
    task automatic write_dcr(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data
    );
        @(master_cb);
        master_cb.wr_valid <= 1'b1;
        master_cb.wr_addr  <= addr;
        master_cb.wr_data  <= data;
        
        @(master_cb);
        master_cb.wr_valid <= 1'b0;
    endtask
    
    // Task: Write multiple DCRs
    task automatic write_dcr_burst(
        input logic [ADDR_WIDTH-1:0] addr_queue[$],
        input logic [DATA_WIDTH-1:0] data_queue[$]
    );
        for (int i = 0; i < addr_queue.size(); i++) begin
            write_dcr(addr_queue[i], data_queue[i]);
        end
    endtask

    // //==========================================================================
    // // PROTOCOL ASSERTIONS
    // //==========================================================================
    
    // // DCR write should be single-cycle pulse
    // property wr_valid_pulse_p;
    //     @(posedge clk) disable iff (!reset_n)
    //     wr_valid |=> !wr_valid;
    // endproperty
    
    // // Address and data must be stable when valid
    // property wr_addr_stable_p;
    //     @(posedge clk) disable iff (!reset_n)
    //     $rose(wr_valid) |-> $stable(wr_addr) throughout ##1 !wr_valid;
    // endproperty
    
    // property wr_data_stable_p;
    //     @(posedge clk) disable iff (!reset_n)
    //     $rose(wr_valid) |-> $stable(wr_data) throughout ##1 !wr_valid;
    // endproperty
    
    // // Assertions (as warnings since multi-cycle writes might be intentional)
    // assert_wr_valid_pulse: assert property (wr_valid_pulse_p)
    //     else $warning("[VORTEX_DCR_IF] wr_valid held high for multiple cycles");
    
    // assert_wr_addr_stable: assert property (wr_addr_stable_p)
    //     else $error("[VORTEX_DCR_IF] wr_addr changed while wr_valid high!");
    
    // assert_wr_data_stable: assert property (wr_data_stable_p)
    //     else $error("[VORTEX_DCR_IF] wr_data changed while wr_valid high!");

    // //==========================================================================
    // // COVERAGE
    // //==========================================================================
    
    // covergroup dcr_write_cg @(posedge clk);
    //     option.per_instance = 1;
        
    //     // Coverage of DCR addresses accessed
    //     wr_addr_cp: coverpoint wr_addr iff (wr_valid) {
    //         bins startup_addr0 = {`VX_DCR_BASE_STARTUP_ADDR0};
    //         bins startup_addr1 = {`VX_DCR_BASE_STARTUP_ADDR0 + 4};
    //         bins num_cores     = {`VX_DCR_BASE_STARTUP_ADDR0 + 8};
    //         bins mpm_class     = {`VX_DCR_BASE_MPM_CLASS};
    //         bins other[] = default;
    //     }
        
    //     // Coverage of write patterns
    //     wr_valid_cp: coverpoint wr_valid {
    //         bins idle   = {0};
    //         bins active = {1};
    //         bins idle_to_active = (0 => 1);
    //         bins active_to_idle = (1 => 0);
    //     }
        
    //     // Data patterns (for common values)
    //     wr_data_cp: coverpoint wr_data iff (wr_valid) {
    //         bins zero       = {32'h00000000};
    //         bins startup_0  = {32'h80000000};
    //         bins startup_1  = {32'h80010000};
    //         bins small_val  = {[1:16]};
    //         bins other[]    = default;
    //     }
    // endgroup
    
    // dcr_write_cg dcr_cov = new();

    //==========================================================================
    // MONITOR: Automatic DCR Write Logging
    //==========================================================================
    
    always @(posedge clk) begin
        if (reset_n && wr_valid) begin
            $display("[DCR_IF @ %0t] Write: %s [0x%h] = 0x%h",
                $time, decode_dcr_addr(wr_addr), wr_addr, wr_data);
        end
    end

    //==========================================================================
    // INITIAL SIGNAL VALUES
    //==========================================================================
    
    initial begin
        wr_valid = 1'b0;
        wr_addr  = '0;
        wr_data  = '0;
    end

endinterface : vortex_dcr_if

`endif // VORTEX_DCR_IF_SV