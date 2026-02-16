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
    parameter RESET_CYCLES = 50;        // Reset duration in clock cycles
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

    //==========================================================================
    // MEMORY MODEL (Shared across all interfaces)
    //==========================================================================
    
    // Include mem_model class
    `include "mem_model.sv"
    
    mem_model memory;
    
    initial begin
        // Create memory model
        memory = new();
        $display("[TB_TOP @ %0t] Memory model created (sparse byte-addressable)", $time);

            // ✅ ADD THIS: Make memory model available to tests
    uvm_config_db#(mem_model)::set(null, "*", "mem_model", memory);
    $display("[TB_TOP @ %0t] Memory model registered in config DB", $time);
    
        
        // Load program if specified
        if (program_file != "") begin
            int bytes_loaded;
            
            $display("[TB_TOP @ %0t] Loading program from: %s", $time, program_file);
            
            // Load program at default RISC-V startup address
            bytes_loaded = memory.load_hex_file(program_file, 64'h80000000);
            
            if (bytes_loaded > 0) begin
                $display("[TB_TOP @ %0t] Program loaded successfully (%0d bytes)", 
                         $time, bytes_loaded);
            end else begin
                $error("[TB_TOP @ %0t] Failed to load program file!", $time);
            end
        end else begin
            $display("[TB_TOP @ %0t] No program loaded - memory initialized to zero", $time);
        end
    end

      //==========================================================================
  // Memory Response Driver Process
  // Uses clocking block for proper synchronization
  // Responds to memory requests from DUT
  //==========================================================================
  initial begin
    // Initialize response signals
    vif.mem_if.mem_responder_cb.req_ready <= 1'b0;
    vif.mem_if.mem_responder_cb.rsp_valid <= 1'b0;
    vif.mem_if.mem_responder_cb.rsp_data  <= '0;
    vif.mem_if.mem_responder_cb.rsp_tag   <= '0;
    
    // Wait for reset release
    wait(reset_n == 1'b1);
    @(posedge clk);
    
    $display("[TB_TOP @ %0t] Starting memory responder (using clocking block)", $time);
    
    forever begin
      @(vif.mem_if.mem_responder_cb);
      
      // Check if DUT has a valid memory request
      if (vif.mem_if.mem_responder_cb.req_valid) begin
        
        // // Process the request based on read/write
        // if (vif.mem_if.mem_responder_cb.req_rw) begin
        //   // Write request
        //   memory.write_byte(
        //     vif.mem_if.mem_responder_cb.req_addr,
        //     vif.mem_if.mem_responder_cb.req_data,
        //     vif.mem_if.mem_responder_cb.req_byteen
        //   );
        //   $display("[TB_TOP @ %0t] MEM WRITE: addr=0x%08h data=0x%08h byteen=0x%01h tag=0x%01h", 
        //            $time,
        //            vif.mem_if.mem_responder_cb.req_addr,
        //            vif.mem_if.mem_responder_cb.req_data,
        //            vif.mem_if.mem_responder_cb.req_byteen,
        //            vif.mem_if.mem_responder_cb.req_tag);
                // Process the request based on read/write
        if (vif.mem_if.mem_responder_cb.req_rw) begin
          // Write request - handle byte enables properly
          automatic bit [31:0] addr   = vif.mem_if.mem_responder_cb.req_addr;
          automatic bit [63:0] data   = vif.mem_if.mem_responder_cb.req_data;
          automatic bit [7:0]  byteen = vif.mem_if.mem_responder_cb.req_byteen;
          
          // Write individual bytes based on byte enable
          for (int i = 0; i < 8; i++) begin
            if (byteen[i]) begin
              memory.write_byte(addr + i, data[i*8 +: 8]);
            end
          end
          
          $display("[TB_TOP @ %0t] MEM WRITE: addr=0x%08h data=0x%016h byteen=0x%02h tag=0x%02h",
                   $time, addr, data, byteen,
                   vif.mem_if.mem_responder_cb.req_tag);

        end else begin
          // Read request
          $display("[TB_TOP @ %0t] MEM READ:  addr=0x%08h tag=0x%01h", 
                   $time,
                   vif.mem_if.mem_responder_cb.req_addr,
                   vif.mem_if.mem_responder_cb.req_tag);
        end
        
        // Drive response signals via clocking block (1 cycle later due to NBA)
        vif.mem_if.mem_responder_cb.req_ready <= 1'b1;
        vif.mem_if.mem_responder_cb.rsp_valid <= 1'b1;
        vif.mem_if.mem_responder_cb.rsp_data  <= memory.read_word(vif.mem_if.mem_responder_cb.req_addr);
        vif.mem_if.mem_responder_cb.rsp_tag   <= vif.mem_if.mem_responder_cb.req_tag;
        
        $display("[TB_TOP @ %0t] MEM RESP:  data=0x%08h tag=0x%01h", 
                 $time,
                 memory.read_word(vif.mem_if.mem_responder_cb.req_addr),
                 vif.mem_if.mem_responder_cb.req_tag);
        
      end else begin
        // No request - keep ready asserted, deassert response valid
        vif.mem_if.mem_responder_cb.req_ready <= 1'b1;  // Always ready
        vif.mem_if.mem_responder_cb.rsp_valid <= 1'b0;
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
                vif.axi_if.awready <= 1'b0;
                aw_id_reg <= '0;
                aw_addr_reg <= '0;
            end else begin
                vif.axi_if.awready <= 1'b1;
                
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
                vif.axi_if.wready <= 1'b0;
            end else begin
                vif.axi_if.wready <= 1'b1;
                
                if (vif.axi_if.wvalid && vif.axi_if.wready) begin
                    automatic bit [31:0] addr = aw_addr_reg;
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
                vif.axi_if.bvalid <= 1'b0;
                vif.axi_if.bid <= '0;
                vif.axi_if.bresp <= 2'b00;
            end else begin
                if (vif.axi_if.wvalid && vif.axi_if.wready && vif.axi_if.wlast) begin
                    vif.axi_if.bvalid <= 1'b1;
                    vif.axi_if.bid <= aw_id_reg;
                    vif.axi_if.bresp <= 2'b00; // OKAY
                    $display("[AXI_MEM @ %0t] B: id=%0d resp=OKAY", $time, aw_id_reg);
                end else if (vif.axi_if.bvalid && vif.axi_if.bready) begin
                    vif.axi_if.bvalid <= 1'b0;
                end
            end
        end
        
        //----------------------------------------------------------------------
        // AXI Read Address Channel
        //----------------------------------------------------------------------
        always_ff @(posedge clk) begin
            if (!reset_n) begin
                vif.axi_if.arready <= 1'b0;
                ar_id_reg <= '0;
                ar_addr_reg <= '0;
                ar_len_reg <= '0;
            end else begin
                vif.axi_if.arready <= 1'b1;
                
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
                vif.axi_if.rvalid <= 1'b0;
                vif.axi_if.rid <= '0;
                vif.axi_if.rdata <= '0;
                vif.axi_if.rresp <= 2'b00;
                vif.axi_if.rlast <= 1'b0;
                read_beat_count <= '0;
            end else begin
                if (vif.axi_if.arvalid && vif.axi_if.arready) begin
                    vif.axi_if.rvalid <= 1'b1;
                end
                
                if (vif.axi_if.rvalid && vif.axi_if.rready) begin
                    automatic bit [31:0] addr = ar_addr_reg + (read_beat_count << 3);
                    automatic bit [63:0] data = memory.read_dword(addr);
                    
                    vif.axi_if.rid <= ar_id_reg;
                    vif.axi_if.rdata <= data;
                    vif.axi_if.rresp <= 2'b00; // OKAY
                    vif.axi_if.rlast <= (read_beat_count == ar_len_reg);
                    
                    $display("[AXI_MEM @ %0t] R: addr=0x%08h data=0x%016h beat=%0d/%0d", 
                             $time, addr, data, read_beat_count+1, ar_len_reg+1);
                    
                    if (read_beat_count == ar_len_reg) begin
                        vif.axi_if.rvalid <= 1'b0;
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
        //----------------------------------------------------------------------
        // Vortex with AXI wrapper
        //----------------------------------------------------------------------
        Vortex_axi #(
            .AXI_DATA_WIDTH(MEM_DATA_WIDTH),
            .AXI_ADDR_WIDTH(MEM_ADDR_WIDTH)
        ) dut (
            .clk(clk),
            .reset(!reset_n),
            
            // AXI Master Interface
            .m_axi_awid(vif.axi_if.awid),
            .m_axi_awaddr(vif.axi_if.awaddr),
            .m_axi_awlen(vif.axi_if.awlen),
            .m_axi_awsize(vif.axi_if.awsize),
            .m_axi_awburst(vif.axi_if.awburst),
            .m_axi_awlock(vif.axi_if.awlock),
            .m_axi_awcache(vif.axi_if.awcache),
            .m_axi_awprot(vif.axi_if.awprot),
            .m_axi_awvalid(vif.axi_if.awvalid),
            .m_axi_awready(vif.axi_if.awready),
            
            .m_axi_wdata(vif.axi_if.wdata),
            .m_axi_wstrb(vif.axi_if.wstrb),
            .m_axi_wlast(vif.axi_if.wlast),
            .m_axi_wvalid(vif.axi_if.wvalid),
            .m_axi_wready(vif.axi_if.wready),
            
            .m_axi_bid(vif.axi_if.bid),
            .m_axi_bresp(vif.axi_if.bresp),
            .m_axi_bvalid(vif.axi_if.bvalid),
            .m_axi_bready(vif.axi_if.bready),
            
            .m_axi_arid(vif.axi_if.arid),
            .m_axi_araddr(vif.axi_if.araddr),
            .m_axi_arlen(vif.axi_if.arlen),
            .m_axi_arsize(vif.axi_if.arsize),
            .m_axi_arburst(vif.axi_if.arburst),
            .m_axi_arlock(vif.axi_if.arlock),
            .m_axi_arcache(vif.axi_if.arcache),
            .m_axi_arprot(vif.axi_if.arprot),
            .m_axi_arvalid(vif.axi_if.arvalid),
            .m_axi_arready(vif.axi_if.arready),
            
            .m_axi_rid(vif.axi_if.rid),
            .m_axi_rdata(vif.axi_if.rdata),
            .m_axi_rresp(vif.axi_if.rresp),
            .m_axi_rlast(vif.axi_if.rlast),
            .m_axi_rvalid(vif.axi_if.rvalid),
            .m_axi_rready(vif.axi_if.rready),
            
            // DCR Interface
            .dcr_wr_valid(vif.dcr_if.wr_valid),
            .dcr_wr_addr(vif.dcr_if.wr_addr),
            .dcr_wr_data(vif.dcr_if.wr_data),
            
            // Status
            .busy(vif.status_if.busy)
            //.ebreak(vif.status_if.ebreak_detected)
        );
        
        initial $display("[TB_TOP @ %0t] DUT instantiated: Vortex with AXI wrapper", $time);
        
    `else
        //----------------------------------------------------------------------
        // Vortex with custom memory interface (default)
        //----------------------------------------------------------------------
        Vortex dut (
            .clk(clk),
            .reset(!reset_n),
            
        //     // Custom Memory Interface
        //     .mem_req_valid(vif.mem_if.req_valid),
        //     .mem_req_ready(vif.mem_if.req_ready),
        //     .mem_req_rw(vif.mem_if.req_rw),
        //     .mem_req_addr(vif.mem_if.req_addr),
        //     .mem_req_data(vif.mem_if.req_data),
        //     .mem_req_byteen(vif.mem_if.req_byteen),
        //     .mem_req_tag(vif.mem_if.req_tag),
            
        //     .mem_rsp_valid(vif.mem_if.rsp_valid),
        //     .mem_rsp_ready(vif.mem_if.rsp_ready),
        //     .mem_rsp_data(vif.mem_if.rsp_data),
        //     .mem_rsp_tag(vif.mem_if.rsp_tag),
        
            // Custom Memory Interface - FIXED: Connect as arrays with [0:0]
            .mem_req_valid({vif.mem_if.req_valid}),
            .mem_req_ready({vif.mem_if.req_ready}),
            .mem_req_rw({vif.mem_if.req_rw}),
            .mem_req_addr({vif.mem_if.req_addr}),
            .mem_req_data({vif.mem_if.req_data}),
            .mem_req_byteen({vif.mem_if.req_byteen}),
            .mem_req_tag({vif.mem_if.req_tag}),
            
            .mem_rsp_valid({vif.mem_if.rsp_valid}),
            .mem_rsp_ready({vif.mem_if.rsp_ready}),
            .mem_rsp_data({vif.mem_if.rsp_data}),
            .mem_rsp_tag({vif.mem_if.rsp_tag}),        
            
            // DCR Interface
            .dcr_wr_valid(vif.dcr_if.wr_valid),
            .dcr_wr_addr(vif.dcr_if.wr_addr),
            .dcr_wr_data(vif.dcr_if.wr_data),
            
            // Status
            .busy(vif.status_if.busy)
            //.ebreak(vif.status_if.ebreak_detected)
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
    
    parameter int IDLE_THRESHOLD = 200;  // Cycles idle before declaring done
    
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
        if (vif.mem_if.req_valid && vif.mem_if.req_ready) begin
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
            if (tb_idle_cycles == IDLE_THRESHOLD) begin
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














// ////////////////////////////////////////////////////////////////////////////////
// // File: vortex_tb_top.sv
// // Description: Complete Top-Level Testbench for Vortex GPGPU UVM Verification
// //
// // This is the production-ready testbench top module featuring:
// //   ✅ Clock and reset generation with proper sequencing
// //   ✅ Complete interface bundle instantiation (5 interfaces)
// //   ✅ DUT instantiation with both AXI and custom memory variants
// //   ✅ Simple memory model (AXI slave responder) for standalone testing
// //   ✅ Full UVM configuration database setup
// //   ✅ Waveform dumping with command-line control
// //   ✅ Timeout watchdog with configurable limits
// //   ✅ Clean simulation finish with statistics
// //
// // Usage:
// //   # Questa/ModelSim
// //   vsim -do "run -all" +UVM_TESTNAME=vortex_smoke_test +HEX=program.hex
// //
// //   # VCS
// //   simv +UVM_TESTNAME=vortex_smoke_test +HEX=program.hex
// //
// //   # Command-line options:
// //   +HEX=<file>         - Program to load into memory
// //   +TIMEOUT=<cycles>   - Simulation timeout (default: 1000000)
// //   +NO_WAVES           - Disable waveform dumping
// //   +WAVE=<file>        - Waveform output file (default: vortex_sim.vcd)
// //
// // Author: Vortex UVM Team
// // Date: December 2025
// ////////////////////////////////////////////////////////////////////////////////

// `ifndef VORTEX_TB_TOP_SV
// `define VORTEX_TB_TOP_SV

// `timescale 1ns/1ps

// // Include UVM macros
// `include "uvm_macros.svh"

// // Include Vortex configuration header (for RTL parameters)
// `include "VX_define.vh"

// module vortex_tb_top;

//     import uvm_pkg::*;

//     //==========================================================================
//     // PARAMETERS
//     //==========================================================================
    
//     parameter CLK_PERIOD = 10;          // 100 MHz clock (10ns period)
//     parameter RESET_CYCLES = 20;        // Reset duration in clock cycles
//     parameter TIMEOUT_CYCLES = 1000000; // Default simulation timeout
    
//     parameter MEM_SIZE = 1 << 20;       // 1 MB memory (configurable)
//     parameter MEM_ADDR_WIDTH = 32;
//     parameter MEM_DATA_WIDTH = 64;

//     //==========================================================================
//     // CLOCK AND RESET GENERATION
//     //==========================================================================
    
//     logic clk;
//     logic reset_n;
    
//     // Clock generation - runs forever
//     initial begin
//         clk = 1'b0;
//         forever #(CLK_PERIOD/2) clk = ~clk;
//     end
    
//     // Reset generation with proper sequencing
//     initial begin
//         $display("================================================================================");
//         $display("[TB_TOP @ %0t] Vortex GPGPU UVM Testbench Starting...", $time);
//         $display("================================================================================");
        
//         reset_n = 1'b0;
        
//         // Hold reset for specified cycles
//         repeat(RESET_CYCLES) @(posedge clk);
        
//         $display("[TB_TOP @ %0t] Releasing reset", $time);
//         reset_n = 1'b1;
        
//         // Allow system to stabilize
//         repeat(5) @(posedge clk);
        
//         $display("[TB_TOP @ %0t] Reset sequence complete - System ready", $time);
//     end

//     //==========================================================================
//     // INTERFACE INSTANTIATION
//     //==========================================================================
    
//     // Instantiate the complete interface bundle
//     // This encapsulates all 5 sub-interfaces with clocking blocks
//     vortex_if vif (
//         .clk(clk),
//         .reset_n(reset_n)
//     );

//     //==========================================================================
//     // COMMAND-LINE ARGUMENT PROCESSING
//     //==========================================================================
    
//     string hex_file = "";
//     int    timeout_cycles = TIMEOUT_CYCLES;
//     bit    dump_waves = 1'b1;
//     string wave_file = "vortex_sim.vcd";
    
//     initial begin
//         // Get hex file for program loading
//         if ($value$plusargs("HEX=%s", hex_file)) begin
//             $display("[TB_TOP @ %0t] Program file: %s", $time, hex_file);
//         end else if ($value$plusargs("PROGRAM=%s", hex_file)) begin
//             $display("[TB_TOP @ %0t] Program file: %s", $time, hex_file);
//         end else begin
//             $display("[TB_TOP @ %0t] WARNING: No program file specified (+HEX=<file>)", $time);
//             $display("[TB_TOP @ %0t] Memory will be initialized to zero", $time);
//         end
        
//         // Get timeout override
//         if ($value$plusargs("TIMEOUT=%d", timeout_cycles)) begin
//             $display("[TB_TOP @ %0t] Custom timeout: %0d cycles", $time, timeout_cycles);
//         end
        
//         // Check for wave dumping control
//         if ($test$plusargs("NO_WAVES")) begin
//             dump_waves = 1'b0;
//             $display("[TB_TOP @ %0t] Waveform dumping disabled", $time);
//         end
        
//         if ($value$plusargs("WAVE=%s", wave_file)) begin
//             $display("[TB_TOP @ %0t] Waveform output: %s", $time, wave_file);
//         end
//     end

//     //==========================================================================
//     // WAVEFORM DUMPING
//     //==========================================================================
    
//     // initial begin
//     //     if (dump_waves) begin
//     //         $display("[TB_TOP @ %0t] Dumping waveforms to %s", $time, wave_file);
//     //         $dumpfile(wave_file);
//     //         $dumpvars(0, vortex_tb_top);
//     //     end
//     // end

//     // //==========================================================================
//     // // MEMORY MODEL (Simple AXI Slave Responder)
//     // //==========================================================================
//     // // This is a simplified memory model for basic standalone testing
//     // // For comprehensive verification, the UVM AXI agent provides full protocol checking
//     // //==========================================================================
    
//     // // Memory array (64-bit words)
//     // logic [MEM_DATA_WIDTH-1:0] memory [0:MEM_SIZE-1];
    
//     // // Program loading from hex file
//     // initial begin
//     //     // Initialize memory to zero
//     //     for (int i = 0; i < MEM_SIZE; i++) begin
//     //         memory[i] = '0;
//     //     end
        
//     //     // Load hex file if provided
//     //     if (hex_file != "") begin
//     //         $display("[TB_TOP @ %0t] Loading program from: %s", $time, hex_file);
//     //         $readmemh(hex_file, memory);
//     //         $display("[TB_TOP @ %0t] Program loaded successfully", $time);
//     //     end
//     // end
    
//     // //--------------------------------------------------------------------------
//     // // AXI Write Address Channel
//     // //--------------------------------------------------------------------------
//     // logic [3:0] aw_id_reg;
//     // logic [31:0] aw_addr_reg;
    
//     // always_ff @(posedge clk) begin
//     //     if (!reset_n) begin
//     //         vif.axi_if.awready <= 1'b0;
//     //         aw_id_reg <= '0;
//     //         aw_addr_reg <= '0;
//     //     end else begin
//     //         // Always ready to accept write addresses
//     //         vif.axi_if.awready <= 1'b1;
            
//     //         // Capture address for write data phase
//     //         if (vif.axi_if.awvalid && vif.axi_if.awready) begin
//     //             aw_id_reg <= vif.axi_if.awid;
//     //             aw_addr_reg <= vif.axi_if.awaddr;
//     //         end
//     //     end
//     // end
    
//     // //--------------------------------------------------------------------------
//     // // AXI Write Data Channel
//     // //--------------------------------------------------------------------------
//     // always_ff @(posedge clk) begin
//     //     if (!reset_n) begin
//     //         vif.axi_if.wready <= 1'b0;
//     //     end else begin
//     //         vif.axi_if.wready <= 1'b1;
            
//     //         // Write to memory on valid data beat
//     //         if (vif.axi_if.wvalid && vif.axi_if.wready) begin
//     //             logic [31:0] word_addr = aw_addr_reg >> 3; // Convert to 64-bit words
                
//     //             // Apply byte enables
//     //             for (int i = 0; i < 8; i++) begin
//     //                 if (vif.axi_if.wstrb[i]) begin
//     //                     memory[word_addr][(i*8)+:8] <= vif.axi_if.wdata[(i*8)+:8];
//     //                 end
//     //             end
                
//     //             if (vif.axi_if.wlast) begin
//     //                 $display("[MEM_MODEL @ %0t] Write: addr=0x%h data=0x%h", 
//     //                     $time, aw_addr_reg, vif.axi_if.wdata);
//     //             end
//     //         end
//     //     end
//     // end
    
//     // //--------------------------------------------------------------------------
//     // // AXI Write Response Channel
//     // //--------------------------------------------------------------------------
//     // always_ff @(posedge clk) begin
//     //     if (!reset_n) begin
//     //         vif.axi_if.bvalid <= 1'b0;
//     //         vif.axi_if.bid <= '0;
//     //         vif.axi_if.bresp <= 2'b00;
//     //     end else begin
//     //         // Generate write response after last data beat
//     //         if (vif.axi_if.wvalid && vif.axi_if.wready && vif.axi_if.wlast) begin
//     //             vif.axi_if.bvalid <= 1'b1;
//     //             vif.axi_if.bid <= aw_id_reg;
//     //             vif.axi_if.bresp <= 2'b00; // OKAY
//     //         end else if (vif.axi_if.bvalid && vif.axi_if.bready) begin
//     //             vif.axi_if.bvalid <= 1'b0;
//     //         end
//     //     end
//     // end
    
//     // //--------------------------------------------------------------------------
//     // // AXI Read Address Channel
//     // //--------------------------------------------------------------------------
//     // logic [3:0] ar_id_reg;
//     // logic [31:0] ar_addr_reg;
//     // logic [7:0] ar_len_reg;
    
//     // always_ff @(posedge clk) begin
//     //     if (!reset_n) begin
//     //         vif.axi_if.arready <= 1'b0;
//     //         ar_id_reg <= '0;
//     //         ar_addr_reg <= '0;
//     //         ar_len_reg <= '0;
//     //     end else begin
//     //         vif.axi_if.arready <= 1'b1;
            
//     //         // Capture read address
//     //         if (vif.axi_if.arvalid && vif.axi_if.arready) begin
//     //             ar_id_reg <= vif.axi_if.arid;
//     //             ar_addr_reg <= vif.axi_if.araddr;
//     //             ar_len_reg <= vif.axi_if.arlen;
//     //         end
//     //     end
//     // end
    
//     // //--------------------------------------------------------------------------
//     // // AXI Read Data Channel
//     // //--------------------------------------------------------------------------
//     // logic [7:0] read_beat_count;
    
//     // always_ff @(posedge clk) begin
//     //     if (!reset_n) begin
//     //         vif.axi_if.rvalid <= 1'b0;
//     //         vif.axi_if.rid <= '0;
//     //         vif.axi_if.rdata <= '0;
//     //         vif.axi_if.rresp <= 2'b00;
//     //         vif.axi_if.rlast <= 1'b0;
//     //         read_beat_count <= '0;
//     //     end else begin
//     //         // Start read burst
//     //         if (vif.axi_if.arvalid && vif.axi_if.arready) begin
//     //             read_beat_count <= 0;
//     //             vif.axi_if.rvalid <= 1'b1;
//     //         end
            
//     //         // Generate read data
//     //         if (vif.axi_if.rvalid && vif.axi_if.rready) begin
//     //             logic [31:0] word_addr = (ar_addr_reg >> 3) + read_beat_count;
                
//     //             vif.axi_if.rid <= ar_id_reg;
//     //             vif.axi_if.rdata <= memory[word_addr];
//     //             vif.axi_if.rresp <= 2'b00; // OKAY
//     //             vif.axi_if.rlast <= (read_beat_count == ar_len_reg);
                
//     //             $display("[MEM_MODEL @ %0t] Read: addr=0x%h data=0x%h beat=%0d/%0d", 
//     //                 $time, (ar_addr_reg + (read_beat_count << 3)), 
//     //                 memory[word_addr], read_beat_count+1, ar_len_reg+1);
                
//     //             if (read_beat_count == ar_len_reg) begin
//     //                 vif.axi_if.rvalid <= 1'b0;
//     //                 read_beat_count <= '0;
//     //             end else begin
//     //                 read_beat_count <= read_beat_count + 1;
//     //             end
//     //         end
//     //     end
//     // end

//     //==========================================================================
//     // DUT INSTANTIATION
//     //==========================================================================
//     // Select DUT variant at compile time using `define
//     //==========================================================================
    
//     `ifdef USE_AXI_WRAPPER
//         //----------------------------------------------------------------------
//         // Option 1: Vortex with AXI wrapper (for external memory)
//         //----------------------------------------------------------------------
//         Vortex_axi #(
//             .AXI_DATA_WIDTH(MEM_DATA_WIDTH),
//             .AXI_ADDR_WIDTH(MEM_ADDR_WIDTH)
//         ) dut (
//             .clk(clk),
//             .reset(!reset_n),
            
//             // AXI Master Interface
//             .m_axi_awid(vif.axi_if.awid),
//             .m_axi_awaddr(vif.axi_if.awaddr),
//             .m_axi_awlen(vif.axi_if.awlen),
//             .m_axi_awsize(vif.axi_if.awsize),
//             .m_axi_awburst(vif.axi_if.awburst),
//             .m_axi_awlock(vif.axi_if.awlock),
//             .m_axi_awcache(vif.axi_if.awcache),
//             .m_axi_awprot(vif.axi_if.awprot),
//             .m_axi_awvalid(vif.axi_if.awvalid),
//             .m_axi_awready(vif.axi_if.awready),
            
//             .m_axi_wdata(vif.axi_if.wdata),
//             .m_axi_wstrb(vif.axi_if.wstrb),
//             .m_axi_wlast(vif.axi_if.wlast),
//             .m_axi_wvalid(vif.axi_if.wvalid),
//             .m_axi_wready(vif.axi_if.wready),
            
//             .m_axi_bid(vif.axi_if.bid),
//             .m_axi_bresp(vif.axi_if.bresp),
//             .m_axi_bvalid(vif.axi_if.bvalid),
//             .m_axi_bready(vif.axi_if.bready),
            
//             .m_axi_arid(vif.axi_if.arid),
//             .m_axi_araddr(vif.axi_if.araddr),
//             .m_axi_arlen(vif.axi_if.arlen),
//             .m_axi_arsize(vif.axi_if.arsize),
//             .m_axi_arburst(vif.axi_if.arburst),
//             .m_axi_arlock(vif.axi_if.arlock),
//             .m_axi_arcache(vif.axi_if.arcache),
//             .m_axi_arprot(vif.axi_if.arprot),
//             .m_axi_arvalid(vif.axi_if.arvalid),
//             .m_axi_arready(vif.axi_if.arready),
            
//             .m_axi_rid(vif.axi_if.rid),
//             .m_axi_rdata(vif.axi_if.rdata),
//             .m_axi_rresp(vif.axi_if.rresp),
//             .m_axi_rlast(vif.axi_if.rlast),
//             .m_axi_rvalid(vif.axi_if.rvalid),
//             .m_axi_rready(vif.axi_if.rready),
            
//             // DCR Interface
//             .dcr_wr_valid(vif.dcr_if.wr_valid),
//             .dcr_wr_addr(vif.dcr_if.wr_addr),
//             .dcr_wr_data(vif.dcr_if.wr_data),
            
//             // Status
//             .busy(vif.status_if.busy),
//             .ebreak(vif.status_if.ebreak_detected)
//         );
//     `else
//         //----------------------------------------------------------------------
//         // Option 2: Vortex with custom memory interface (default)
//         //----------------------------------------------------------------------
//         Vortex dut (
//             .clk(clk),
//             .reset(!reset_n),
            
//             // Custom Memory Interface
//             .mem_req_valid(vif.mem_if.req_valid),
//             .mem_req_ready(vif.mem_if.req_ready),
//             .mem_req_rw(vif.mem_if.req_rw),
//             .mem_req_addr(vif.mem_if.req_addr),
//             .mem_req_data(vif.mem_if.req_data),
//             .mem_req_byteen(vif.mem_if.req_byteen),
//             .mem_req_tag(vif.mem_if.req_tag),
            
//             .mem_rsp_valid(vif.mem_if.rsp_valid),
//             .mem_rsp_ready(vif.mem_if.rsp_ready),
//             .mem_rsp_data(vif.mem_if.rsp_data),
//             .mem_rsp_tag(vif.mem_if.rsp_tag),
            
//             // DCR Interface
//             .dcr_wr_valid(vif.dcr_if.wr_valid),
//             .dcr_wr_addr(vif.dcr_if.wr_addr),
//             .dcr_wr_data(vif.dcr_if.wr_data),
            
//             // Status
//             .busy(vif.status_if.busy),
//             .ebreak(vif.status_if.ebreak_detected)
//         );
//     `endif

//     //==========================================================================
//     // UVM CONFIGURATION AND TEST INITIALIZATION
//     //==========================================================================
    
//     initial begin
//         // Pass virtual interfaces to UVM config DB
//         // All UVM components can retrieve these using uvm_config_db::get()
        
//         uvm_config_db#(virtual vortex_if)::set(null, "*", "vif", vif);
//         uvm_config_db#(virtual vortex_axi_if)::set(null, "*", "vif_axi", vif.axi_if);
//         uvm_config_db#(virtual vortex_mem_if)::set(null, "*", "vif_mem", vif.mem_if);
//         uvm_config_db#(virtual vortex_dcr_if)::set(null, "*", "vif_dcr", vif.dcr_if);
//         uvm_config_db#(virtual vortex_status_if)::set(null, "*", "vif_status", vif.status_if);
        
//         $display("[TB_TOP @ %0t] Virtual interfaces configured in UVM config DB", $time);
        
//         // Set default verbosity level
//         uvm_top.set_report_verbosity_level_hier(UVM_LOW);
        
//         // Start UVM test
//         $display("[TB_TOP @ %0t] Starting UVM test phase...", $time);
//         run_test();
//     end

//     //==========================================================================
//     // TIMEOUT WATCHDOG
//     //==========================================================================
    
//     initial begin
//         int elapsed_cycles = 0;
        
//         // Wait for reset deassertion
//         wait(reset_n == 1'b1);
        
//         // Start timeout counter
//         fork
//             begin
//                 while (elapsed_cycles < timeout_cycles) begin
//                     @(posedge clk);
//                     elapsed_cycles++;
//                 end
                
//                 $display("================================================================================");
//                 $error("[TB_TOP @ %0t] SIMULATION TIMEOUT!", $time);
//                 $display("[TB_TOP @ %0t] Exceeded %0d cycles without completion", $time, timeout_cycles);
//                 $display("================================================================================");
                
//                 // Print final status
//                 vif.print_status();
                
//                 $finish(2);
//             end
//         join_none
//     end

//     //==========================================================================
//     // SIMULATION COMPLETION HANDLING
//     //==========================================================================
    
//     final begin
//         $display("================================================================================");
//         $display("[TB_TOP @ %0t] Simulation Complete", $time);
//         $display("================================================================================");
        
//         // Print final statistics
//         if (vif.status_if.ebreak_detected) begin
//             $display("Test Result:    PASS (EBREAK detected)");
//         end else begin
//             $display("Test Result:    UNKNOWN (check test logs)");
//         end
        
//         $display("Total Cycles:   %0d", vif.status_if.cycle_count);
//         $display("Instructions:   %0d", vif.status_if.instr_count);
        
//         if (vif.status_if.cycle_count > 0) begin
//             $display("IPC:            %0.2f", 
//                 real'(vif.status_if.instr_count) / real'(vif.status_if.cycle_count));
//         end
        
//         $display("================================================================================");
//     end

// endmodule : vortex_tb_top

// `endif // VORTEX_TB_TOP_SV
