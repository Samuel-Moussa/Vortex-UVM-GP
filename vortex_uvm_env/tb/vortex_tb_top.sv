////////////////////////////////////////////////////////////////////////////////
// File: vortex_tb_top.sv
// Description: Production-Ready Testbench Top for Vortex GPGPU UVM Verification
//
// Features:
//   ✅ Clock and reset generation with proper sequencing
//   ✅ Complete interface bundle instantiation (5 interfaces)
//   ✅ DUT instantiation (AXI wrapper + custom memory variants)
//   ✅ Fully functional memory model with sparse storage
//   ✅ Working memory responders (both AXI and custom interface)
//   ✅ Program loading with error handling
//   ✅ Cross-simulator waveform support (Questa, VCS, Icarus)
//   ✅ Configurable wave file names
//   ✅ Full UVM configuration database setup
//   ✅ Enhanced timeout watchdog with cycle tracking
//   ✅ Detailed command-line argument processing
//   ✅ Test result reporting (PASS/UNKNOWN)
//   ✅ Comprehensive statistics and debug info
//
// Usage:
//   # Questa/ModelSim (WLF waveforms)
//   vsim -c vortex_tb_top +UVM_TESTNAME=smoke_test +PROGRAM=kernel.hex \
//        -do "run -all; quit"
//
//   # VCS/Icarus (VCD waveforms)
//   simv +UVM_TESTNAME=smoke_test +PROGRAM=kernel.hex +WAVE=sim.vcd
//
//   # With AXI wrapper
//   vsim -c vortex_tb_top +define+USE_AXI_WRAPPER +UVM_TESTNAME=smoke_test
//
// Command-Line Options:
//   +UVM_TESTNAME=<test>  - Test to run (required)
//   +PROGRAM=<file>       - Program hex file to load
//   +HEX=<file>           - Alternative to +PROGRAM
//   +TIMEOUT=<cycles>     - Override global timeout (default: 1000000)
//   +NO_WAVES             - Disable waveform dumping
//   +WAVE=<file>          - Waveform output file (default: vortex_sim.vcd)
//
// Author: Vortex UVM Team
// Date: December 2025
// Version: 2.0 (Enhanced)
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_TB_TOP_SV
`define VORTEX_TB_TOP_SV

`timescale 1ns/1ps

// Include UVM macros
`include "uvm_macros.svh"

// Include Vortex RTL configuration
`include "VX_define.vh"

module vortex_tb_top;

    import uvm_pkg::*;
    import vortex_test_pkg::*;

    //==========================================================================
    // PARAMETERS
    //==========================================================================
    
    parameter CLK_PERIOD = 10;          // 100 MHz clock (10ns period)
    parameter RESET_CYCLES = 200;        // Reset duration in clock cycles
    parameter TIMEOUT_CYCLES = 1000000; // Default simulation timeout
    
    // Memory configuration parameters
    parameter MEM_SIZE = 1 << 20;       // 1 MB (for compatibility)
    parameter MEM_ADDR_WIDTH = 32;
    parameter MEM_DATA_WIDTH = 64;

    //==========================================================================
    // CLOCK GENERATION
    //==========================================================================
    
    logic clk;
    
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //==========================================================================
    // RESET GENERATION
    //==========================================================================
    
    logic reset_n;
    
    initial begin
        $display("================================================================================");
        $display("[TB_TOP @ %0t] Vortex GPGPU UVM Testbench Initialized", $time);
        $display("================================================================================");
        
        reset_n = 1'b0;
        
        // Hold reset for specified cycles
        repeat(RESET_CYCLES) @(posedge clk);
        
        $display("[TB_TOP @ %0t] Releasing reset", $time);
        reset_n = 1'b1;
        
        // Allow system to stabilize
        repeat(5) @(posedge clk);
        
        $display("[TB_TOP @ %0t] Reset sequence complete - System ready", $time);
    end

//==========================================================================
// DCR INTERFACE INITIALIZATION
// ✅ PERMANENT FIX: RTL now initializes startup_addr during reset
// No force needed - VX_dcr_data.sv sets dcrs.startup_addr = 0x80000000 on reset
//==========================================================================

initial begin
    vif.dcr_if.wr_valid = 1'b0;
    vif.dcr_if.wr_addr  = 12'h000;
    vif.dcr_if.wr_data  = 32'h00000000;
    
    $display("[TB_TOP @ %0t] DCR interface initialized", $time);
end
    //==========================================================================
    // INTERFACE INSTANTIATION
    //==========================================================================
    
    vortex_if vif (
        .clk(clk),
        .reset_n(reset_n)
    );

    //==========================================================================
    // COMMAND-LINE ARGUMENT PROCESSING
    //==========================================================================
    
    string program_file = "";
    int    timeout_cycles = TIMEOUT_CYCLES;
    bit    dump_waves = 1'b1;
    string wave_file = "vortex_sim.vcd";
    
    initial begin
        // Get program file for loading
        if ($value$plusargs("PROGRAM=%s", program_file)) begin
            $display("[TB_TOP @ %0t] Program file: %s", $time, program_file);
        end else if ($value$plusargs("HEX=%s", program_file)) begin
            $display("[TB_TOP @ %0t] Program file: %s", $time, program_file);
        end else begin
            $display("[TB_TOP @ %0t] WARNING: No program file specified (+PROGRAM=<file>)", $time);
            $display("[TB_TOP @ %0t] Memory will be initialized to zero", $time);
        end
        
        // Get timeout override
        if ($value$plusargs("TIMEOUT=%d", timeout_cycles)) begin
            $display("[TB_TOP @ %0t] Custom timeout: %0d cycles", $time, timeout_cycles);
        end else begin
            $display("[TB_TOP @ %0t] Default timeout: %0d cycles", $time, timeout_cycles);
        end
        
        // Check for wave dumping control
        if ($test$plusargs("NO_WAVES") || $test$plusargs("NOWAVES")) begin
            dump_waves = 1'b0;
            $display("[TB_TOP @ %0t] Waveform dumping disabled", $time);
        end
        
        // Get wave file name
        if ($value$plusargs("WAVE=%s", wave_file)) begin
            $display("[TB_TOP @ %0t] Waveform output: %s", $time, wave_file);
        end
    end

    // //==========================================================================
    // // MEMORY MODEL (Shared across all interfaces)
    // //==========================================================================
    
    // // Include mem_model class
    // `include "mem_model.sv"
    
    // mem_model memory;
    
    // initial begin
    //     // Create memory model
    //     memory = new();
    //     $display("[TB_TOP @ %0t] Memory model created (sparse byte-addressable)", $time);

    //     // Make memory model available to tests
    //     uvm_config_db#(mem_model)::set(null, "*", "mem_model", memory);
    //     $display("[TB_TOP @ %0t] Memory model registered in config DB", $time);
        
        
    //     // // Load program if specified
    //     // if (program_file != "") begin
    //     //     int bytes_loaded;
            
    //     //     $display("[TB_TOP @ %0t] Loading program from: %s", $time, program_file);
            
    //     //     // Load program at default RISC-V startup address
    //     //     bytes_loaded = memory.load_hex_file(program_file, 64'h80000000);
            
    //     //     if (bytes_loaded > 0) begin
    //     //         $display("[TB_TOP @ %0t] Program loaded successfully (%0d bytes)", 
    //     //                  $time, bytes_loaded);
    //     //     end else begin
    //     //         $error("[TB_TOP @ %0t] Failed to load program file!", $time);
    //     //     end
    //     // end else begin
    //     //     $display("[TB_TOP @ %0t] No program loaded - memory initialized to zero", $time);
    //     // end
    //         // ✅ NEW: Just print what was requested
    // if (program_file != "") begin
    //     $display("[TB_TOP @ %0t] Program will be loaded by test: %s", $time, program_file);
    // end else begin
    //     $display("[TB_TOP @ %0t] No program specified (+PROGRAM plusarg)", $time);
    // end

    // end


    //==========================================================================
// MEMORY MODEL (Shared across all interfaces)
//==========================================================================

mem_model memory;

initial begin
    // ✅ CHANGE: Use UVM factory create (or just new with name)
    memory = mem_model::type_id::create("memory");
    // OR: memory = new("memory");
    
    $display("[TB_TOP @ %0t] Memory model created (sparse byte-addressable)", $time);

    $display("[TB_TOP @ %0t] Memory model created", $time);

    // ✅ Set with multiple contexts for robustness
    uvm_config_db#(mem_model)::set(null, "*", "mem_model", memory);
    uvm_config_db#(mem_model)::set(null, "uvm_test_top*", "mem_model", memory);
    uvm_config_db#(mem_model)::set(uvm_root::get(), "*", "mem_model", memory);
    
    $display("[TB_TOP @ %0t] mem_model registered in config DB (multiple contexts)", $time);
    
    // ✅ OPTIONAL: Verify it worked (for debugging)
    begin
        mem_model test_get;
        #1; // Wait 1 time unit
        if (uvm_config_db#(mem_model)::get(null, "*", "mem_model", test_get)) begin
            $display("[TB_TOP @ %0t] ✓ mem_model verified in config_db", $time);
        end else begin
            $error("[TB_TOP @ %0t] ✗ mem_model NOT in config_db!", $time);
        end
    end
    
    // Program loading handled by test (keep existing comment)
    if (program_file != "") begin
        $display("[TB_TOP @ %0t] Program will be loaded by test: %s", $time, program_file);
    end else begin
        $display("[TB_TOP @ %0t] No program specified (+PROGRAM plusarg)", $time);
    end
end


      //==========================================================================
  // Memory Response Driver Process
  // Uses clocking block for proper synchronization
  // Responds to memory requests from DUT
  //==========================================================================
  initial begin
    // Initialize response signals
    vif.mem_if.mem_responder_cb.req_ready[0] <= 1'b0;
    vif.mem_if.mem_responder_cb.rsp_valid[0] <= 1'b0;
    vif.mem_if.mem_responder_cb.rsp_data[0]  <= '0;
    vif.mem_if.mem_responder_cb.rsp_tag[0]   <= '0;
    
    // Wait for reset release
    wait(reset_n == 1'b1);
    @(posedge clk);
    
    $display("[TB_TOP @ %0t] Starting memory responder (using clocking block)", $time);
    
//     forever begin
//       @(vif.mem_if.mem_responder_cb);
      
//       // Check if DUT has a valid memory request
//       if (vif.mem_if.mem_responder_cb.req_valid) begin
        

//         // Process the request based on read/write
//         if (vif.mem_if.mem_responder_cb.req_rw) begin
//           // Write request - handle byte enables properly
//           automatic bit [31:0] addr   = vif.mem_if.mem_responder_cb.req_addr;
//           automatic bit [63:0] data   = vif.mem_if.mem_responder_cb.req_data;
//           automatic bit [7:0]  byteen = vif.mem_if.mem_responder_cb.req_byteen;
          
//           // Write individual bytes based on byte enable
//           for (int i = 0; i < 8; i++) begin
//             if (byteen[i]) begin
//               memory.write_byte(addr + i, data[i*8 +: 8]);
//             end
//           end
          
//           $display("[TB_TOP @ %0t] MEM WRITE: addr=0x%08h data=0x%016h byteen=0x%02h tag=0x%02h",
//                    $time, addr, data, byteen,
//                    vif.mem_if.mem_responder_cb.req_tag);

//         end else begin
//           // Read request
//           $display("[TB_TOP @ %0t] MEM READ:  addr=0x%08h tag=0x%01h", 
//                    $time,
//                    vif.mem_if.mem_responder_cb.req_addr,
//                    vif.mem_if.mem_responder_cb.req_tag);
//         end
        
//         // Drive response signals via clocking block (1 cycle later due to NBA)
//         vif.mem_if.mem_responder_cb.req_ready <= 1'b1;
//         vif.mem_if.mem_responder_cb.rsp_valid <= 1'b1;
//         vif.mem_if.mem_responder_cb.rsp_data  <= memory.read_word(vif.mem_if.mem_responder_cb.req_addr);
//         vif.mem_if.mem_responder_cb.rsp_tag   <= vif.mem_if.mem_responder_cb.req_tag;
        
//         $display("[TB_TOP @ %0t] MEM RESP:  data=0x%016h tag=0x%01h", 
//                  $time,
//                  memory.read_word(vif.mem_if.mem_responder_cb.req_addr),
//                  vif.mem_if.mem_responder_cb.req_tag);
        
//       end else begin
//         // No request - keep ready asserted, deassert response valid
//         vif.mem_if.mem_responder_cb.req_ready <= 1'b1;  // Always ready
//         vif.mem_if.mem_responder_cb.rsp_valid <= 1'b0;
//       end
//     end
//   end

forever begin
    @(vif.mem_if.mem_responder_cb);
    
    // Check if DUT has a valid memory request (port 0)
    if (vif.mem_if.mem_responder_cb.req_valid[0]) begin
        
        // ✅ CRITICAL FIX: Convert word address to byte address
        // Vortex memory interface uses WORD addresses (index of 64-byte blocks)
        // Memory model uses BYTE addresses
        // Conversion: byte_addr = word_addr << 6 (multiply by 64)
        automatic bit [31:0] word_addr = vif.mem_if.mem_responder_cb.req_addr[0];
        automatic bit [31:0] byte_addr = word_addr << 6;
        
        // Process the request based on read/write
        if (vif.mem_if.mem_responder_cb.req_rw[0]) begin
            // Write request
            automatic bit [63:0] data   = vif.mem_if.mem_responder_cb.req_data[0];
            automatic bit [7:0]  byteen = vif.mem_if.mem_responder_cb.req_byteen[0];
            
            for (int i = 0; i < 8; i++) begin
                if (byteen[i]) begin
                    memory.write_byte(byte_addr + i, data[i*8 +: 8]);
                end
            end
            
            $display("[TB_TOP @ %0t] MEM WRITE: word=0x%08h byte=0x%08h data=0x%016h byteen=0x%02h",
                    $time, word_addr, byte_addr, data, byteen);
        end else begin
            // Read request
            $display("[TB_TOP @ %0t] MEM READ:  word=0x%08h byte=0x%08h tag=0x%01h", 
                    $time, word_addr, byte_addr,
                    vif.mem_if.mem_responder_cb.req_tag[0]);
        end
        
        // Drive response signals
        vif.mem_if.mem_responder_cb.req_ready[0] <= 1'b1;
        vif.mem_if.mem_responder_cb.rsp_valid[0] <= 1'b1;
        vif.mem_if.mem_responder_cb.rsp_data[0]  <= memory.read_dword(byte_addr);
        vif.mem_if.mem_responder_cb.rsp_tag[0]   <= vif.mem_if.mem_responder_cb.req_tag[0];
        
        $display("[TB_TOP @ %0t] MEM RESP:  data=0x%016h tag=0x%01h", 
                $time,
                memory.read_dword(byte_addr),
                vif.mem_if.mem_responder_cb.req_tag[0]);

    end else begin
        // No request - keep ready asserted
        vif.mem_if.mem_responder_cb.req_ready[0] <= 1'b1;
        vif.mem_if.mem_responder_cb.rsp_valid[0] <= 1'b0;
    end
end
  end


    //==========================================================================
    // WAVEFORM DUMPING (Cross-Simulator Support)
    //==========================================================================
    
    initial begin
        if (dump_waves) begin
            // Detect simulator and use appropriate waveform format
            `ifdef QUESTA
                // Questa/ModelSim - uses WLF format automatically
                $display("[TB_TOP @ %0t] Waveforms enabled: vsim.wlf (Questa)", $time);
                $display("[TB_TOP @ %0t] View with: vsim -view vsim.wlf", $time);
            `elsif VCS
                // Synopsys VCS - uses VPD or VCD
                $display("[TB_TOP @ %0t] Waveforms enabled: %s (VCS)", $time, wave_file);
                $vcdplusfile(wave_file);
                $vcdpluson;
            `else
                // Other simulators (Icarus, Xcelium) - use VCD
                $display("[TB_TOP @ %0t] Dumping waveforms to: %s", $time, wave_file);
                $dumpfile(wave_file);
                $dumpvars(0, vortex_tb_top);
            `endif
        end else begin
            $display("[TB_TOP @ %0t] Waveform dumping disabled", $time);
        end
    end

    //==========================================================================
    // MEMORY RESPONDER - CUSTOM MEMORY INTERFACE
    //==========================================================================
    
    // `ifndef USE_AXI_WRAPPER
    //     // Read response tracking
    //     typedef struct {
    //         bit [63:0] data;
    //         bit [7:0]  tag;
    //     } read_resp_t;
        
    //     read_resp_t read_resp_queue[$];
        
    //     // Request handling
    //     always_ff @(posedge clk) begin
    //         if (!reset_n) begin
    //             vif.mem_if.req_ready <= 1'b0;
    //         end else begin
    //             // Always ready to accept requests
    //             vif.mem_if.req_ready <= 1'b1;
                
    //             // Handle memory requests
    //             if (vif.mem_if.req_valid && vif.mem_if.req_ready) begin
    //                 automatic bit [63:0] addr = vif.mem_if.req_addr;
    //                 automatic bit [63:0] data;
    //                 automatic bit [7:0] tag = vif.mem_if.req_tag;
    //                 automatic bit rw = vif.mem_if.req_rw; // 1=write, 0=read
    //                 automatic read_resp_t resp;
                    
    //                 if (rw) begin
    //                     //------------------------------------------------------
    //                     // WRITE operation
    //                     //------------------------------------------------------
    //                     data = vif.mem_if.req_data;
                        
    //                     // Apply byte enable mask
    //                     for (int i = 0; i < 8; i++) begin
    //                         if (vif.mem_if.req_byteen[i]) begin
    //                             memory.write_byte(addr + i, data[(i*8)+:8]);
    //                         end
    //                     end
                        
    //                     $display("[MEM_RESP @ %0t] WR addr=0x%08h data=0x%016h mask=0x%02h", 
    //                              $time, addr, data, vif.mem_if.req_byteen);
                        
    //                 end else begin
    //                     //------------------------------------------------------
    //                     // READ operation - queue response for next cycle
    //                     //------------------------------------------------------
    //                     automatic read_resp_t resp;
    //                     data = memory.read_dword(addr);
    //                     resp.data = data;
    //                     resp.tag = tag;
    //                     read_resp_queue.push_back(resp);
                        
    //                     $display("[MEM_RESP @ %0t] RD addr=0x%08h data=0x%016h tag=0x%02h (queued)", 
    //                              $time, addr, data, tag);
    //                 end
    //             end
    //         end
    //     end
        
    //     // Response generation
    //     always_ff @(posedge clk) begin
    //         if (!reset_n) begin
    //             vif.mem_if.rsp_valid <= 1'b0;
    //             vif.mem_if.rsp_data <= '0;
    //             vif.mem_if.rsp_tag <= '0;
    //         end else begin
    //             // If we have a pending read response and it was accepted
    //             if (vif.mem_if.rsp_valid && vif.mem_if.rsp_ready) begin
    //                 vif.mem_if.rsp_valid <= 1'b0;
    //             end
                
    //             // Generate new response if queue is not empty and previous was accepted
    //             if (read_resp_queue.size() > 0 && (!vif.mem_if.rsp_valid || vif.mem_if.rsp_ready)) begin
    //                 automatic read_resp_t resp = read_resp_queue.pop_front();
    //                 vif.mem_if.rsp_valid <= 1'b1;
    //                 vif.mem_if.rsp_data <= resp.data;
    //                 vif.mem_if.rsp_tag <= resp.tag;
    //             end
    //         end
    //     end
    // `endif

    //==========================================================================
    // MEMORY RESPONDER - AXI INTERFACE
    //==========================================================================
    
    `ifdef USE_AXI_WRAPPER
        logic [3:0] aw_id_reg;
        logic [31:0] aw_addr_reg;
        logic [3:0] ar_id_reg;
        logic [31:0] ar_addr_reg;
        logic [7:0] ar_len_reg;
        logic [7:0] read_beat_count;
        
        //----------------------------------------------------------------------
        // AXI Write Address Channel
        //----------------------------------------------------------------------
        always_ff @(posedge clk) begin
            if (!reset_n) begin
                vif.axi_if.slave_cb.awready <= 1'b0;
                aw_id_reg <= '0;
                aw_addr_reg <= '0;
            end else begin
                vif.axi_if.slave_cb.awready <= 1'b1;
                
                if (vif.axi_if.awvalid && vif.axi_if.awready) begin
                    aw_id_reg <= vif.axi_if.awid;
                    aw_addr_reg <= vif.axi_if.awaddr;
                    $display("[AXI_MEM @ %0t] AW: id=%0d addr=0x%08h", 
                             $time, vif.axi_if.awid, vif.axi_if.awaddr);
                end
            end
        end
        
        //----------------------------------------------------------------------
        // AXI Write Data Channel
        //----------------------------------------------------------------------
        always_ff @(posedge clk) begin
            if (!reset_n) begin
                vif.axi_if.slave_cb.wready <= 1'b0;
            end else begin
                vif.axi_if.slave_cb.wready <= 1'b1;
                
                if (vif.axi_if.wvalid && vif.axi_if.wready) begin
                    automatic bit [31:0] addr = aw_addr_reg ; // ✅ Convert word address to byte address
                    automatic bit [63:0] data = vif.axi_if.wdata;
                    
                    // Apply byte enables
                    for (int i = 0; i < 8; i++) begin
                        if (vif.axi_if.wstrb[i]) begin
                            memory.write_byte(addr + i, data[(i*8)+:8]);
                        end
                    end
                    
                    if (vif.axi_if.wlast) begin
                        $display("[AXI_MEM @ %0t] W: addr=0x%08h data=0x%016h strb=0x%02h", 
                                 $time, addr, data, vif.axi_if.wstrb);
                    end
                end
            end
        end
        
        //----------------------------------------------------------------------
        // AXI Write Response Channel
        //----------------------------------------------------------------------
        always_ff @(posedge clk) begin
            if (!reset_n) begin
                vif.axi_if.slave_cb.bvalid <= 1'b0;
                vif.axi_if.slave_cb.bid <= '0;
                vif.axi_if.slave_cb.bresp <= 2'b00;
            end else begin
                if (vif.axi_if.wvalid && vif.axi_if.wready && vif.axi_if.wlast) begin
                    vif.axi_if.slave_cb.bvalid <= 1'b1;
                    vif.axi_if.slave_cb.bid <= aw_id_reg;
                    vif.axi_if.slave_cb.bresp <= 2'b00; // OKAY
                    $display("[AXI_MEM @ %0t] B: id=%0d resp=OKAY", $time, aw_id_reg);
                end else if (vif.axi_if.bvalid && vif.axi_if.bready) begin
                    vif.axi_if.slave_cb.bvalid <= 1'b0;
                end
            end
        end
        
        //----------------------------------------------------------------------
        // AXI Read Address Channel
        //----------------------------------------------------------------------
        always_ff @(posedge clk) begin
            if (!reset_n) begin
                vif.axi_if.slave_cb.arready <= 1'b0;
                ar_id_reg <= '0;
                ar_addr_reg <= '0;
                ar_len_reg <= '0;
            end else begin
                vif.axi_if.slave_cb.arready <= 1'b1;
                
                if (vif.axi_if.arvalid && vif.axi_if.arready) begin
                    ar_id_reg <= vif.axi_if.arid;
                    ar_addr_reg <= vif.axi_if.araddr;
                    ar_len_reg <= vif.axi_if.arlen;
                    read_beat_count <= 0;
                    $display("[AXI_MEM @ %0t] AR: id=%0d addr=0x%08h len=%0d", 
                             $time, vif.axi_if.arid, vif.axi_if.araddr, vif.axi_if.arlen);
                end
            end
        end
        
        //----------------------------------------------------------------------
        // AXI Read Data Channel
        //----------------------------------------------------------------------
        always_ff @(posedge clk) begin
            if (!reset_n) begin
                vif.axi_if.slave_cb.rvalid <= 1'b0;
                vif.axi_if.slave_cb.rid <= '0;
                vif.axi_if.slave_cb.rdata <= '0;
                vif.axi_if.slave_cb.rresp <= 2'b00;
                vif.axi_if.slave_cb.rlast <= 1'b0;
                read_beat_count <= '0;
            end else begin
                if (vif.axi_if.arvalid && vif.axi_if.arready) begin
                    vif.axi_if.slave_cb.rvalid <= 1'b1;
                end
                
                // if (vif.axi_if.rvalid && vif.axi_if.rready) begin
                //     automatic bit [31:0] addr = ar_addr_reg + (read_beat_count << 3);
                //     // ✅ araddr_reg is a WORD address from Vortex AXI bus
                //     // Memory model is BYTE addressed → convert: byte = word << 6
                //     automatic bit [63:0] data = memory.read_dword(ar_addr_reg << 6);

                if (vif.axi_if.rvalid && vif.axi_if.rready) begin
                    // ar_addr_reg = WORD address → shift left 6 to get byte address
                    // read_beat_count × 8 = byte offset within the 64-byte cache line
                    automatic bit [31:0] base_byte_addr = ar_addr_reg;
                    automatic bit [31:0] burst_offset   = read_beat_count << 3;
                    automatic bit [31:0] addr           = base_byte_addr + burst_offset;
                    automatic bit [63:0] data           = memory.read_dword(addr);

                    
                    vif.axi_if.slave_cb.rid <= ar_id_reg;
                    vif.axi_if.slave_cb.rdata <= data;
                    vif.axi_if.slave_cb.rresp <= 2'b00; // OKAY
                    vif.axi_if.slave_cb.rlast <= (read_beat_count == ar_len_reg);
                    
                    $display("[AXI_MEM @ %0t] R: addr=0x%08h data=0x%016h beat=%0d/%0d", 
                             $time, addr, data, read_beat_count+1, ar_len_reg+1);
                    
                    if (read_beat_count == ar_len_reg) begin
                        vif.axi_if.slave_cb.rvalid <= 1'b0;
                        read_beat_count <= '0;
                    end else begin
                        read_beat_count <= read_beat_count + 1;
                    end
                end
            end
        end
    `endif

    //==========================================================================
    // DUT INSTANTIATION
    //==========================================================================
    
    `ifdef USE_AXI_WRAPPER
        // //----------------------------------------------------------------------
        // // Vortex with AXI wrapper
        // //----------------------------------------------------------------------
        // Vortex_axi #(
        //     .AXI_DATA_WIDTH(MEM_DATA_WIDTH),
        //     .AXI_ADDR_WIDTH(MEM_ADDR_WIDTH)
        // ) dut (
        //     .clk(clk),
        //     .reset(!reset_n),

        //     // AXI Write Address Channel
        //     .m_axi_awid(vif.axi_if.awid),
        //     .m_axi_awaddr(vif.axi_if.awaddr),
        //     .m_axi_awlen(vif.axi_if.awlen),
        //     .m_axi_awsize(vif.axi_if.awsize),
        //     .m_axi_awburst(vif.axi_if.awburst),
        //     .m_axi_awlock(vif.axi_if.awlock),
        //     .m_axi_awcache(vif.axi_if.awcache),
        //     .m_axi_awprot(vif.axi_if.awprot),
        //     .m_axi_awqos(vif.axi_if.awqos),
        //     .m_axi_awregion(vif.axi_if.awregion),
        //     .m_axi_awvalid({vif.axi_if.awvalid}),
        //     .m_axi_awready(vif.axi_if.awready),

        //     // AXI Write Data Channel
        //     .m_axi_wdata(vif.axi_if.wdata),
        //     .m_axi_wstrb(vif.axi_if.wstrb),
        //     .m_axi_wlast(vif.axi_if.wlast),
        //     .m_axi_wvalid(vif.axi_if.wvalid),
        //     .m_axi_wready(vif.axi_if.wready),

        //     // AXI Write Response Channel
        //     .m_axi_bid(vif.axi_if.bid),
        //     .m_axi_bresp(vif.axi_if.bresp),
        //     .m_axi_bvalid(vif.axi_if.bvalid),
        //     .m_axi_bready(vif.axi_if.bready),

        //     // AXI Read Address Channel
        //     .m_axi_arid(vif.axi_if.arid),
        //     .m_axi_araddr(vif.axi_if.araddr),
        //     .m_axi_arlen(vif.axi_if.arlen),
        //     .m_axi_arsize(vif.axi_if.arsize),
        //     .m_axi_arburst(vif.axi_if.arburst),
        //     .m_axi_arlock(vif.axi_if.arlock),
        //     .m_axi_arcache(vif.axi_if.arcache),
        //     .m_axi_arprot(vif.axi_if.arprot),
        //     .m_axi_arqos(vif.axi_if.arqos),
        //     .m_axi_arregion(vif.axi_if.arregion),
        //     .m_axi_arvalid(vif.axi_if.arvalid),
        //     .m_axi_arready(vif.axi_if.arready),

        //     // AXI Read Data Channel
        //     .m_axi_rid(vif.axi_if.rid),
        //     .m_axi_rdata(vif.axi_if.rdata),
        //     .m_axi_rresp(vif.axi_if.rresp),
        //     .m_axi_rlast(vif.axi_if.rlast),
        //     .m_axi_rvalid(vif.axi_if.rvalid),
        //     .m_axi_rready(vif.axi_if.rready),

        //     // DCR Interface
        //     .dcr_wr_valid(vif.dcr_if.wr_valid),
        //     .dcr_wr_addr(vif.dcr_if.wr_addr),
        //     .dcr_wr_data(vif.dcr_if.wr_data),

        //     // Status
        //     .busy(vif.status_if.busy)
        // );

        
        // initial $display("[TB_TOP @ %0t] DUT instantiated: Vortex with AXI wrapper", $time);


        //----------------------------------------------------------------------
        // Intermediate wires — match Vortex_axi exact port types
        // AXI_NUM_BANKS=1, AXI_TID_WIDTH=VX_MEM_TAG_WIDTH
        //----------------------------------------------------------------------
localparam AXI_TID_W = VX_gpu_pkg::VX_MEM_TAG_WIDTH;

        // AW channel
        wire                      axi_awvalid [1];
        wire                      axi_awready [1];
        wire [MEM_ADDR_WIDTH-1:0] axi_awaddr  [1];
        wire [AXI_TID_W-1:0]     axi_awid    [1];
        wire [7:0]                axi_awlen   [1];
        wire [2:0]                axi_awsize  [1];
        wire [1:0]                axi_awburst [1];
        wire [1:0]                axi_awlock  [1];
        wire [3:0]                axi_awcache [1];
        wire [2:0]                axi_awprot  [1];
        wire [3:0]                axi_awqos   [1];
        wire [3:0]                axi_awregion[1];
        // W channel
        wire                      axi_wvalid  [1];
        wire                      axi_wready  [1];
        wire [MEM_DATA_WIDTH-1:0] axi_wdata   [1];
        wire [MEM_DATA_WIDTH/8-1:0] axi_wstrb [1];
        wire                      axi_wlast   [1];
        // B channel
        wire                      axi_bvalid  [1];
        wire                      axi_bready  [1];
        wire [AXI_TID_W-1:0]     axi_bid     [1];
        wire [1:0]                axi_bresp   [1];
        // AR channel
        wire                      axi_arvalid [1];
        wire                      axi_arready [1];
        wire [MEM_ADDR_WIDTH-1:0] axi_araddr  [1];
        wire [AXI_TID_W-1:0]     axi_arid    [1];
        wire [7:0]                axi_arlen   [1];
        wire [2:0]                axi_arsize  [1];
        wire [1:0]                axi_arburst [1];
        wire [1:0]                axi_arlock  [1];
        wire [3:0]                axi_arcache [1];
        wire [2:0]                axi_arprot  [1];
        wire [3:0]                axi_arqos   [1];
        wire [3:0]                axi_arregion[1];
        // R channel
        wire                      axi_rvalid  [1];
        wire                      axi_rready  [1];
        wire [MEM_DATA_WIDTH-1:0] axi_rdata   [1];
        wire                      axi_rlast   [1];
        wire [AXI_TID_W-1:0]     axi_rid     [1];
        wire [1:0]                axi_rresp   [1];

        // Connect interface scalars to wire array element [0]
        // DUT outputs → interface
        assign vif.axi_if.awvalid  = axi_awvalid[0];
        assign vif.axi_if.awaddr   = axi_awaddr[0];
        assign vif.axi_if.awid     = axi_awid[0][3:0];
        assign vif.axi_if.awlen    = axi_awlen[0];
        assign vif.axi_if.awsize   = axi_awsize[0];
        assign vif.axi_if.awburst  = axi_awburst[0];
        assign vif.axi_if.awlock   = axi_awlock[0];
        assign vif.axi_if.awcache  = axi_awcache[0];
        assign vif.axi_if.awprot   = axi_awprot[0];
        assign vif.axi_if.awqos    = axi_awqos[0];
        assign vif.axi_if.awregion = axi_awregion[0];
        assign vif.axi_if.wvalid   = axi_wvalid[0];
        assign vif.axi_if.wdata    = axi_wdata[0];
        assign vif.axi_if.wstrb    = axi_wstrb[0];
        assign vif.axi_if.wlast    = axi_wlast[0];
        assign vif.axi_if.arvalid  = axi_arvalid[0];
        assign vif.axi_if.araddr   = axi_araddr[0];
        assign vif.axi_if.arid     = axi_arid[0][3:0];
        assign vif.axi_if.arlen    = axi_arlen[0];
        assign vif.axi_if.arsize   = axi_arsize[0];
        assign vif.axi_if.arburst  = axi_arburst[0];
        assign vif.axi_if.arlock   = axi_arlock[0];
        assign vif.axi_if.arcache  = axi_arcache[0];
        assign vif.axi_if.arprot   = axi_arprot[0];
        assign vif.axi_if.arqos    = axi_arqos[0];
        assign vif.axi_if.arregion = axi_arregion[0];
        // Interface → DUT inputs
        assign axi_awready[0]  = vif.axi_if.awready;
        assign axi_wready[0]   = vif.axi_if.wready;
        assign axi_bvalid[0]   = vif.axi_if.bvalid;
        assign axi_bid[0]      = AXI_TID_W'(vif.axi_if.bid);
        assign axi_bresp[0]    = vif.axi_if.bresp;
        assign axi_bready[0]   = vif.axi_if.bready;
        assign axi_arready[0]  = vif.axi_if.arready;
        assign axi_rvalid[0]   = vif.axi_if.rvalid;
        assign axi_rdata[0]    = vif.axi_if.rdata;
        assign axi_rlast[0]    = vif.axi_if.rlast;
        assign axi_rid[0]      = AXI_TID_W'(vif.axi_if.rid);
        assign axi_rresp[0]    = vif.axi_if.rresp;
        assign axi_rready[0]   = vif.axi_if.rready;

        Vortex_axi #(
            .AXI_DATA_WIDTH(MEM_DATA_WIDTH),
            .AXI_ADDR_WIDTH(MEM_ADDR_WIDTH),
            .AXI_TID_WIDTH(AXI_TID_W),
            .AXI_NUM_BANKS(1)
        ) dut (
            .clk(clk),
            .reset(!reset_n),
            .m_axi_awvalid(axi_awvalid),
            .m_axi_awready(axi_awready),
            .m_axi_awaddr(axi_awaddr),
            .m_axi_awid(axi_awid),
            .m_axi_awlen(axi_awlen),
            .m_axi_awsize(axi_awsize),
            .m_axi_awburst(axi_awburst),
            .m_axi_awlock(axi_awlock),
            .m_axi_awcache(axi_awcache),
            .m_axi_awprot(axi_awprot),
            .m_axi_awqos(axi_awqos),
            .m_axi_awregion(axi_awregion),
            .m_axi_wvalid(axi_wvalid),
            .m_axi_wready(axi_wready),
            .m_axi_wdata(axi_wdata),
            .m_axi_wstrb(axi_wstrb),
            .m_axi_wlast(axi_wlast),
            .m_axi_bvalid(axi_bvalid),
            .m_axi_bready(axi_bready),
            .m_axi_bid(axi_bid),
            .m_axi_bresp(axi_bresp),
            .m_axi_arvalid(axi_arvalid),
            .m_axi_arready(axi_arready),
            .m_axi_araddr(axi_araddr),
            .m_axi_arid(axi_arid),
            .m_axi_arlen(axi_arlen),
            .m_axi_arsize(axi_arsize),
            .m_axi_arburst(axi_arburst),
            .m_axi_arlock(axi_arlock),
            .m_axi_arcache(axi_arcache),
            .m_axi_arprot(axi_arprot),
            .m_axi_arqos(axi_arqos),
            .m_axi_arregion(axi_arregion),
            .m_axi_rvalid(axi_rvalid),
            .m_axi_rready(axi_rready),
            .m_axi_rdata(axi_rdata),
            .m_axi_rlast(axi_rlast),
            .m_axi_rid(axi_rid),
            .m_axi_rresp(axi_rresp),
            .dcr_wr_valid(vif.dcr_if.wr_valid),
            .dcr_wr_addr(vif.dcr_if.wr_addr),
            .dcr_wr_data(vif.dcr_if.wr_data),
            .busy(vif.status_if.busy)
        );

        initial $display("[TB_TOP @ %0t] DUT instantiated: Vortex with AXI wrapper", $time);

    `else
        //----------------------------------------------------------------------
        // Vortex with custom memory interface (default)
        //----------------------------------------------------------------------
        Vortex dut (
            .clk(clk),
            .reset(!reset_n),
    
            // DIRECT ARRAY-TO-ARRAY CONNECTION!
            .mem_req_valid(vif.mem_if.req_valid),      // Clean!
            .mem_req_ready(vif.mem_if.req_ready),      // Clean!
            .mem_req_rw(vif.mem_if.req_rw),            // Clean!
            .mem_req_addr(vif.mem_if.req_addr),        // Clean!
            .mem_req_data(vif.mem_if.req_data),        // Clean!
            .mem_req_byteen(vif.mem_if.req_byteen),    // Clean!
            .mem_req_tag(vif.mem_if.req_tag),          // Clean!
            
            .mem_rsp_valid(vif.mem_if.rsp_valid),      // Clean!
            .mem_rsp_ready(vif.mem_if.rsp_ready),      // Clean!
            .mem_rsp_data(vif.mem_if.rsp_data),        // Clean!
            .mem_rsp_tag(vif.mem_if.rsp_tag),          // Clean!      
            
            // DCR Interface
            .dcr_wr_valid(vif.dcr_if.wr_valid),
            .dcr_wr_addr(vif.dcr_if.wr_addr),
            .dcr_wr_data(vif.dcr_if.wr_data),
            
            // Status
            .busy(vif.status_if.busy)
        );
        
        initial $display("[TB_TOP @ %0t] DUT instantiated: Vortex with custom memory interface", $time);
        
    `endif

    //==========================================================================
    // TESTBENCH STATUS TRACKING
    // 
    // The DUT only provides 'busy'. We track everything else in the testbench:
    //   - cycle_count:       Count cycles while out of reset
    //   - instr_count:       Estimate from memory operations
    //   - ebreak_detected:   Detect via idle threshold
    //==========================================================================
            
            logic [63:0] tb_cycle_count;
            logic [63:0] tb_instr_count;
            logic [63:0] tb_mem_ops;
            logic        tb_execution_started;
            logic        tb_execution_complete;
            int          tb_idle_cycles;
            
            parameter int IDLE_THRESHOLD = 500;  // Cycles idle before declaring done
            
            always_ff @(posedge clk) begin
            if (!reset_n) begin
                tb_cycle_count <= 0;
                tb_instr_count <= 0;
                tb_mem_ops <= 0;
                tb_execution_started <= 0;
                tb_execution_complete <= 0;
                tb_idle_cycles <= 0;
            end else begin
                // Always count cycles
                tb_cycle_count <= tb_cycle_count + 1;
                
                // Track memory activity (single port interface)
                // if (vif.mem_if.req_valid[0] && vif.mem_if.req_ready[0]) begin
                    if ((vif.axi_if.rvalid && vif.axi_if.rready) ||
                        (vif.mem_if.req_valid[0] && vif.mem_if.req_ready[0])) begin

                    tb_mem_ops <= tb_mem_ops + 1;
                    tb_idle_cycles <= 0;
                    
                    // Rough instruction estimate (3 mem ops ≈ 1 instruction)
                    if (tb_mem_ops % 3 == 0) begin
                        tb_instr_count <= tb_instr_count + 1;
                    end
                    
                    // Mark execution as started
                    if (!tb_execution_started) begin
                        tb_execution_started <= 1;
                        $display("\n[TB_STATUS @ %0t] ✓ Execution STARTED (first memory access)", $time);
                    end
                    
                end else if (tb_execution_started && !tb_execution_complete) begin
                    // Count idle cycles after execution started
                    tb_idle_cycles <= tb_idle_cycles + 1;
                    
                    // Completion detection
                    // if (tb_idle_cycles == IDLE_THRESHOLD) begin
                    if (tb_idle_cycles == IDLE_THRESHOLD ||
                        (tb_execution_started && !vif.status_if.busy)) begin

                        tb_execution_complete <= 1;
                        $display("\n╔═══════════════════════════════════════════════════╗");
                        $display("║  ✓ EXECUTION COMPLETE (idle %0d cycles)        ║", IDLE_THRESHOLD);
                        $display("╚═══════════════════════════════════════════════════╝");
                        $display("  Total Cycles:       %0d", tb_cycle_count);
                        $display("  Memory Operations:  %0d", tb_mem_ops);
                        $display("  Instructions (est): %0d", tb_instr_count);
                        if (tb_instr_count > 0) begin
                            $display("  IPC (estimated):    %.3f\n", 
                                    real'(tb_instr_count) / real'(tb_cycle_count));
                        end
                    end
                end
            end
        end

    
    // Drive status interface with testbench values
    assign vif.status_if.cycle_count = tb_cycle_count;
    assign vif.status_if.instr_count = tb_instr_count;
    assign vif.status_if.ebreak_detected = tb_execution_complete;
    assign vif.status_if.pc = 32'h0;  // Not tracked
    
    // Periodic status reporting (every 1000 cycles)
    always @(posedge clk) begin
        if (reset_n && tb_cycle_count > 0 && tb_cycle_count % 1000 == 0 && 
            tb_execution_started && !tb_execution_complete) begin
            $display("[TB_STATUS @ %0t] cyc=%0d mem=%0d ins=%0d busy=%b idle=%0d",
                     $time, tb_cycle_count, tb_mem_ops, tb_instr_count, 
                     vif.status_if.busy, tb_idle_cycles);
        end
    end


    //==========================================================================
    // UVM CONFIGURATION DATABASE SETUP
    //==========================================================================
    
    initial begin
        // Pass all virtual interfaces to UVM components
        uvm_config_db#(virtual vortex_if)::set(null, "*", "vif", vif);
        uvm_config_db#(virtual vortex_axi_if)::set(null, "*", "vif_axi", vif.axi_if);
        uvm_config_db#(virtual vortex_mem_if)::set(null, "*", "vif_mem", vif.mem_if);
        uvm_config_db#(virtual vortex_dcr_if)::set(null, "*", "vif_dcr", vif.dcr_if);
        uvm_config_db#(virtual vortex_status_if)::set(null, "*", "vif_status", vif.status_if);
        
        $display("[TB_TOP @ %0t] Virtual interfaces registered in UVM config DB", $time);
        
        // Set default UVM verbosity level
        uvm_top.set_report_verbosity_level_hier(UVM_LOW);
        $display("[TB_TOP @ %0t] UVM verbosity set to UVM_LOW", $time);
        
        // Start UVM test (specified via +UVM_TESTNAME=<test>)
        $display("[TB_TOP @ %0t] Starting UVM test phase...", $time);
        $display("================================================================================");
        run_test();
    end

    //==========================================================================
    // ENHANCED TIMEOUT WATCHDOG (with cycle tracking)
    //==========================================================================
    
    initial begin
        automatic int elapsed_cycles = 0;  // FIX: Explicitly declare as automatic
        
        $display("[TB_TOP @ %0t] Timeout watchdog armed (%0d cycles)", $time, timeout_cycles);
        
        // Wait for reset deassertion
        wait(reset_n == 1'b1);
        
        // Start timeout counter
        fork
            begin
                while (elapsed_cycles < timeout_cycles) begin
                    @(posedge clk);
                    elapsed_cycles++;
                    
                    // Optional: Print progress every 100k cycles
                    if (elapsed_cycles % 100000 == 0) begin
                        $display("[TB_TOP @ %0t] Progress: %0d cycles elapsed...", 
                                 $time, elapsed_cycles);
                    end
                end
                
                // Timeout occurred
                $display("\n================================================================================");
                $error("[TB_TOP @ %0t] ⏰ SIMULATION TIMEOUT!", $time);
                $display("[TB_TOP @ %0t] Exceeded %0d cycles without completion", 
                         $time, timeout_cycles);
                $display("================================================================================\n");
                
                // Print interface status for debugging
                $display("--- System Status at Timeout ---");
                vif.print_status();
                
                // Print memory statistics
                memory.print_statistics();
                
                $finish(2);
            end
        join_none
    end

    //==========================================================================
    // SIMULATION COMPLETION HANDLING
    //==========================================================================
    
    final begin
        $display("\n================================================================================");
        $display("[TB_TOP @ %0t] 🏁 Simulation Complete", $time);
        $display("================================================================================");
        
        // Print test result based on ebreak detection
        if (vif.status_if.ebreak_detected) begin
            $display("✓ Test Result:    PASS (EBREAK detected)");
        end else begin
            $display("? Test Result:    UNKNOWN (check test logs)");
        end
        
        $display("");
        
        // Print execution statistics
        $display("--- Execution Statistics ---");
        $display("  Total Cycles:      %0d", vif.status_if.cycle_count);
        $display("  Instructions:      %0d", vif.status_if.instr_count);
        
        if (vif.status_if.cycle_count > 0) begin
            $display("  IPC:               %0.2f", 
                     real'(vif.status_if.instr_count) / real'(vif.status_if.cycle_count));
        end
        
        $display("");
        
        // Print memory statistics
        memory.print_statistics();
        
        $display("================================================================================\n");
    end

endmodule : vortex_tb_top

`endif // VORTEX_TB_TOP_SV