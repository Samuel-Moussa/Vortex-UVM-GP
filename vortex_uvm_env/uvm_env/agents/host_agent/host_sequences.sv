////////////////////////////////////////////////////////////////////////////////
// File: host_sequences.sv
// Description: Host Sequence Library for Vortex GPU Control
//
// This file contains a collection of reusable host sequences for controlling
// the Vortex GPU. Sequences create transactions that the driver executes
// using proper clocking blocks.
//
// Included Sequences:
//   1. host_base_sequence            - Abstract base class with helper methods
//   2. host_reset_sequence           - Reset the device
//   3. host_load_program_sequence    - Load program into memory
//   4. host_configure_dcr_sequence   - Write DCR registers
//   5. host_launch_kernel_sequence   - Start kernel execution
//   6. host_wait_done_sequence       - Wait for completion
//   7. host_read_result_sequence     - Read results from memory
//   8. host_complete_test_sequence   - Full test flow (load→launch→wait→read)
//
// Usage Example:
//   host_complete_test_sequence seq = host_complete_test_sequence::type_id::create("seq");
//   seq.program_path = "tests/vecadd/vecadd.hex";
//   seq.start(env.host_agent.m_sequencer);
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef HOST_SEQUENCES_SV
`define HOST_SEQUENCES_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import host_agent_pkg::*;


//==============================================================================
// Base Host Sequence
// Provides common helper methods for all host sequences
//==============================================================================
class host_base_sequence extends uvm_sequence #(host_transaction);
    `uvm_object_utils(host_base_sequence)
    
    function new(string name = "host_base_sequence");
        super.new(name);
    endfunction
    
    // Helper: Create and send a transaction
    task send_trans(host_transaction trans);
        start_item(trans);
        finish_item(trans);
    endtask
    
endclass : host_base_sequence

//==============================================================================
// Reset Sequence
// Performs device reset
//==============================================================================
class host_reset_sequence extends host_base_sequence;
    `uvm_object_utils(host_reset_sequence)
    
    function new(string name = "host_reset_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        host_transaction trans;
        
        `uvm_info("HOST_SEQ", "Executing reset sequence", UVM_LOW)
        
        trans = host_transaction::type_id::create("reset_trans");
        trans.op_type = host_transaction::HOST_RESET;
        
        send_trans(trans);
    endtask
    
endclass : host_reset_sequence

//==============================================================================
// Load Program Sequence
// Loads program binary into memory
//==============================================================================
class host_load_program_sequence extends host_base_sequence;
    `uvm_object_utils(host_load_program_sequence)
    
    string    program_path;
    rand bit[63:0] load_address;
    
    // Default load address
    constraint default_load_addr_c {
        load_address == 64'h80000000;
    }
    
    function new(string name = "host_load_program_sequence");
        super.new(name);
        program_path = "program.hex";
    endfunction
    
    virtual task body();
        host_transaction trans;
        
        `uvm_info("HOST_SEQ", $sformatf("Loading program: %s at 0x%016h",
            program_path, load_address), UVM_LOW)
        
        trans = host_transaction::type_id::create("load_trans");
        trans.op_type = host_transaction::HOST_LOAD_PROGRAM;
        trans.program_path = program_path;
        trans.load_address = load_address;
        
        // Load program from file
        if (!trans.load_program_from_file(program_path)) begin
            `uvm_error("HOST_SEQ", $sformatf("Failed to load program: %s", program_path))
            return;
        end
        
        send_trans(trans);
    endtask
    
endclass : host_load_program_sequence

//==============================================================================
// Configure DCR Sequence
// Writes a single DCR register
//==============================================================================
class host_configure_dcr_sequence extends host_base_sequence;
    `uvm_object_utils(host_configure_dcr_sequence)
    
    rand bit [31:0] dcr_address;
    rand bit [31:0] dcr_data;
    
    function new(string name = "host_configure_dcr_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        host_transaction trans;
        
        trans = host_transaction::type_id::create("dcr_trans");
        trans.op_type = host_transaction::HOST_CONFIGURE_DCR;
        trans.dcr_address = dcr_address;
        trans.dcr_data = dcr_data;
        
        send_trans(trans);
    endtask
    
endclass : host_configure_dcr_sequence

//==============================================================================
// Launch Kernel Sequence
// Configures and starts kernel execution
//==============================================================================
class host_launch_kernel_sequence extends host_base_sequence;
    `uvm_object_utils(host_launch_kernel_sequence)
    
    rand bit [63:0] startup_address;
    rand bit [31:0] num_cores;
    rand bit [31:0] num_warps;
    rand bit [31:0] num_threads;
    
    // Default configuration
    constraint default_config_c {
        startup_address == 64'h80000000;
        num_cores inside {[1:4]};
        num_warps inside {[1:8]};
        num_threads inside {[1:4]};
    }
    
    function new(string name = "host_launch_kernel_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        host_transaction trans;
        
        `uvm_info("HOST_SEQ", $sformatf(
            "Launching kernel at 0x%016h (cores=%0d, warps=%0d, threads=%0d)",
            startup_address, num_cores, num_warps, num_threads), UVM_LOW)
        
        trans = host_transaction::type_id::create("launch_trans");
        trans.op_type = host_transaction::HOST_LAUNCH_KERNEL;
        trans.startup_address = startup_address;
        trans.num_cores = num_cores;
        trans.num_warps = num_warps;
        trans.num_threads = num_threads;
        
        send_trans(trans);
    endtask
    
endclass : host_launch_kernel_sequence

//==============================================================================
// Wait for Completion Sequence
// Waits for kernel execution to complete
//==============================================================================
class host_wait_done_sequence extends host_base_sequence;
    `uvm_object_utils(host_wait_done_sequence)
    
    rand int timeout_cycles;
    
    // Reasonable timeout range
    constraint reasonable_timeout_c {
        timeout_cycles inside {[1000:100000]};
    }
    
    function new(string name = "host_wait_done_sequence");
        super.new(name);
        timeout_cycles = 10000;
    endfunction
    
    virtual task body();
        host_transaction trans;
        
        `uvm_info("HOST_SEQ", $sformatf("Waiting for completion (timeout=%0d)",
            timeout_cycles), UVM_LOW)
        
        trans = host_transaction::type_id::create("wait_trans");
        trans.op_type = host_transaction::HOST_WAIT_DONE;
        trans.timeout_cycles = timeout_cycles;
        
        send_trans(trans);
        
        if (!trans.completion_flag) begin
            `uvm_error("HOST_SEQ", "Kernel did not complete within timeout!")
        end else begin
            `uvm_info("HOST_SEQ", $sformatf("Kernel completed in %0d cycles",
                trans.get_execution_cycles()), UVM_LOW)
        end
    endtask
    
endclass : host_wait_done_sequence

//==============================================================================
// Read Result Sequence
// Reads result data from memory
//==============================================================================
class host_read_result_sequence extends host_base_sequence;
    `uvm_object_utils(host_read_result_sequence)
    
    rand bit [63:0] result_address;
    rand bit [31:0] result_size;
    
    // Default result configuration
    constraint default_result_c {
        result_address == 64'h80100000;
        result_size inside {[4:1024]};
        result_size[1:0] == 2'b00;  // Word-aligned
    }
    
    function new(string name = "host_read_result_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        host_transaction trans;
        
        `uvm_info("HOST_SEQ", $sformatf("Reading result from 0x%016h (%0d bytes)",
            result_address, result_size), UVM_LOW)
        
        trans = host_transaction::type_id::create("read_trans");
        trans.op_type = host_transaction::HOST_READ_RESULT;
        trans.result_address = result_address;
        trans.result_size = result_size;
        
        send_trans(trans);
        
        // Print first few words of result
        `uvm_info("HOST_SEQ", "Result data (first 4 words):", UVM_MEDIUM)
        for (int i = 0; i < 16 && i < trans.result_data.size(); i += 4) begin
            bit [31:0] word = {trans.result_data[i+3], trans.result_data[i+2],
                               trans.result_data[i+1], trans.result_data[i]};
            `uvm_info("HOST_SEQ", $sformatf("  [0x%016h] = 0x%08h",
                result_address + i, word), UVM_MEDIUM)
        end
    endtask
    
endclass : host_read_result_sequence

//==============================================================================
// Complete Test Sequence
// Full test flow: Reset → Load → Launch → Wait → Read
//==============================================================================
class host_complete_test_sequence extends host_base_sequence;
    `uvm_object_utils(host_complete_test_sequence)
    
    // Configuration parameters
    string      program_path;
    bit [63:0]  load_address;
    bit [63:0]  startup_address;
    bit [63:0]  result_address;
    bit [31:0]  result_size;
    int         timeout_cycles;
    
    function new(string name = "host_complete_test_sequence");
        super.new(name);
        
        // Default values
        program_path = "test.hex";
        load_address = 64'h80000000;
        startup_address = 64'h80000000;
        result_address = 64'h80100000;
        result_size = 64;
        timeout_cycles = 50000;
    endfunction
    
    virtual task body();
        host_reset_sequence         reset_seq;
        host_load_program_sequence  load_seq;
        host_launch_kernel_sequence launch_seq;
        host_wait_done_sequence     wait_seq;
        host_read_result_sequence   read_seq;
        
        `uvm_info("HOST_SEQ", {"\n",
            "========================================\n",
            "  Starting Complete Test Sequence\n",
            "========================================\n",
            $sformatf("  Program:    %s\n", program_path),
            $sformatf("  Load Addr:  0x%016h\n", load_address),
            $sformatf("  Entry:      0x%016h\n", startup_address),
            $sformatf("  Result:     0x%016h (%0d bytes)\n", result_address, result_size),
            $sformatf("  Timeout:    %0d cycles\n", timeout_cycles),
            "========================================\n",
            "  All operations use clocking blocks\n",
            "  for synchronization\n",
            "========================================"
        }, UVM_LOW)
        
        // Step 1: Reset device
        `uvm_info("HOST_SEQ", "Step 1/5: Reset", UVM_LOW)
        reset_seq = host_reset_sequence::type_id::create("reset_seq");
        reset_seq.start(m_sequencer);
        
        // Step 2: Load program into memory
        `uvm_info("HOST_SEQ", "Step 2/5: Load Program", UVM_LOW)
        load_seq = host_load_program_sequence::type_id::create("load_seq");
        load_seq.program_path = program_path;
        load_seq.load_address = load_address;
        load_seq.start(m_sequencer);
        
        // Step 3: Launch kernel
        `uvm_info("HOST_SEQ", "Step 3/5: Launch Kernel", UVM_LOW)
        launch_seq = host_launch_kernel_sequence::type_id::create("launch_seq");
        launch_seq.startup_address = startup_address;
        launch_seq.start(m_sequencer);
        
        // Step 4: Wait for completion
        `uvm_info("HOST_SEQ", "Step 4/5: Wait for Completion", UVM_LOW)
        wait_seq = host_wait_done_sequence::type_id::create("wait_seq");
        wait_seq.timeout_cycles = timeout_cycles;
        wait_seq.start(m_sequencer);
        
        // Step 5: Read results
        `uvm_info("HOST_SEQ", "Step 5/5: Read Results", UVM_LOW)
        read_seq = host_read_result_sequence::type_id::create("read_seq");
        read_seq.result_address = result_address;
        read_seq.result_size = result_size;
        read_seq.start(m_sequencer);
        
        `uvm_info("HOST_SEQ", {"\n",
            "========================================\n",
            "  Complete Test Sequence Finished\n",
            "========================================"
        }, UVM_LOW)
    endtask
    
endclass : host_complete_test_sequence

`endif // HOST_SEQUENCES_SV
