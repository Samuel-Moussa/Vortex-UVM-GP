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
 
    // Configuration — populated in pre_body() from the sequencer's config_db entry.
    // Available to all derived sequences for reading cfg.startup_addr etc.
    vortex_config cfg;
 
    function new(string name = "host_base_sequence");
        super.new(name);
    endfunction
 
    // FIX 2: pre_body() — runs immediately before body(), after m_sequencer is bound.
    // Fetches vortex_config so derived sequences can read cfg.startup_addr,
    // cfg.test_timeout_cycles, etc. rather than using hardcoded defaults.
    virtual task pre_body();
        super.pre_body();
        if (m_sequencer != null) begin
            if (!uvm_config_db#(vortex_config)::get(m_sequencer, "", "cfg", cfg))
                `uvm_warning("HOST_SEQ", "No vortex_config found on sequencer — cfg will be null")
        end
    endtask
 
    // FIX 3: send_trans() intentionally does NOT call randomize().
    // host_transaction has rand fields (op_type) and constraints
    // (valid_config_c, reasonable_timeout_c) that would randomize num_cores,
    // num_warps, timeout_cycles etc. on every call — overwriting values the
    // caller has already set. All fields are set explicitly before send_trans().
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
    bit [63:0] load_address;  // FIX 4: NOT rand — caller sets this, or cfg.startup_addr is used
 
    function new(string name = "host_load_program_sequence");
        super.new(name);
        program_path  = "program.hex";
        load_address  = 64'h80000000;  // RTL default; overridden from cfg in body()
    endfunction
 
    virtual task body();
        host_transaction trans;
 
        // FIX 4: use cfg.startup_addr if available, so +STARTUP_ADDR plusarg is honoured.
        // Caller can also set load_address directly before start() to override.
        if (cfg != null && load_address == 64'h80000000)
            load_address = cfg.startup_addr;
 
        `uvm_info("HOST_SEQ", $sformatf("Loading program: %s at 0x%016h",
            program_path, load_address), UVM_LOW)
 
        // NOTE: In the TB_TOP DCR flow the program is pre-loaded into mem_model
        // directly by the test before reset deasserts. This sequence is provided
        // for future tests that use the host_driver to load via the MEM interface.
        trans = host_transaction::type_id::create("load_trans");
        trans.op_type     = host_transaction::HOST_LOAD_PROGRAM;
        trans.program_path = program_path;
        trans.load_address = load_address;
 
        // FIX 4: guard send_trans — skip if file load fails to avoid sending
        // a partial transaction with uninitialised program_data[].
        if (!trans.load_program_from_file(program_path)) begin
            `uvm_error("HOST_SEQ", $sformatf("Failed to load program: %s — skipping send", program_path))
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
 
    // FIX 5: NOT rand — these are explicitly set by the caller or from cfg.
    // Making them rand caused the solver to ignore caller assignments and
    // hardcode startup_address == 64'h80000000, ignoring +STARTUP_ADDR.
    bit [63:0] startup_address;
    bit [31:0] num_cores;
    bit [31:0] num_warps;
    bit [31:0] num_threads;
 
    function new(string name = "host_launch_kernel_sequence");
        super.new(name);
        // RTL defaults — overridden from cfg in body() if cfg is available
        startup_address = 64'h80000000;
        num_cores       = 1;
        num_warps       = 4;
        num_threads     = 4;
    endfunction
 
    virtual task body();
        host_transaction trans;
 
        // FIX 5: honour +STARTUP_ADDR plusarg via cfg.startup_addr.
        // Only override if caller left startup_address at the default value,
        // so explicit pre-start assignments are preserved.
        if (cfg != null && startup_address == 64'h80000000)
            startup_address = cfg.startup_addr;
        // Similarly pull core/warp/thread counts from cfg to match RTL compile
        if (cfg != null) begin
            if (num_cores   == 1) num_cores   = cfg.num_cores;
            if (num_warps   == 4) num_warps   = cfg.num_warps;
            if (num_threads == 4) num_threads = cfg.num_threads;
        end
 
        `uvm_info("HOST_SEQ", $sformatf(
            "Launching kernel at 0x%016h (cores=%0d warps=%0d threads=%0d)",
            startup_address, num_cores, num_warps, num_threads), UVM_LOW)
 
        trans = host_transaction::type_id::create("launch_trans");
        trans.op_type         = host_transaction::HOST_LAUNCH_KERNEL;
        trans.startup_address = startup_address;
        trans.num_cores       = num_cores;
        trans.num_warps       = num_warps;
        trans.num_threads     = num_threads;
 
        send_trans(trans);
    endtask
 
endclass : host_launch_kernel_sequence
 
//==============================================================================
// Wait for Completion Sequence
// Waits for kernel execution to complete
//==============================================================================
class host_wait_done_sequence extends host_base_sequence;
    `uvm_object_utils(host_wait_done_sequence)
 
    // FIX 6: NOT rand — timeout_cycles is always explicitly set by the caller
    // (e.g. wait_seq.timeout_cycles = cfg.test_timeout_cycles). Making it rand
    // risked the constraint {inside [1000:100000]} overriding the caller's value
    // if randomize() was ever called on this sequence by a parent.
    int timeout_cycles;
 
    function new(string name = "host_wait_done_sequence");
        super.new(name);
        timeout_cycles = 10000;
    endfunction
 
    virtual task body();
        host_transaction trans;
 
        // Use cfg.test_timeout_cycles if caller left the default and cfg is available
        if (cfg != null && timeout_cycles == 10000)
            timeout_cycles = int'(cfg.test_timeout_cycles);
 
        `uvm_info("HOST_SEQ", $sformatf("Waiting for completion (timeout=%0d cycles)",
            timeout_cycles), UVM_LOW)
 
        trans = host_transaction::type_id::create("wait_trans");
        trans.op_type      = host_transaction::HOST_WAIT_DONE;
        trans.timeout_cycles = timeout_cycles;
 
        // FIX 7: host_transaction.do_copy() exists — host_driver MUST write
        // completion_flag back to the ORIGINAL trans object (not a clone) for
        // this check to see the updated value. This is an explicit contract with
        // the host_driver: it must not clone the transaction item for WAIT_DONE ops.
        // If driver clones, completion_flag here will always be 0 (false positive error).
        send_trans(trans);
 
        if (!trans.completion_flag) begin
            `uvm_error("HOST_SEQ", $sformatf(
                "Kernel did not complete within %0d cycles timeout!", timeout_cycles))
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
        
        // FIX 8: guard i+3 access against result_data bounds.
        // Loop already checks i < trans.result_data.size() but accessing [i+3]
        // is still out-of-bounds when result_data has fewer than i+4 elements.
        // Also note: result_data is only valid here if host_driver wrote back to
        // the ORIGINAL trans handle (no clone) — same contract as completion_flag.
        if (trans.result_data.size() > 0) begin
            `uvm_info("HOST_SEQ", "Result data (first 4 words):", UVM_MEDIUM)
            for (int i = 0; i < 16 && (i + 4) <= trans.result_data.size(); i += 4) begin
                bit [31:0] word = {trans.result_data[i+3], trans.result_data[i+2],
                                   trans.result_data[i+1], trans.result_data[i]};
                `uvm_info("HOST_SEQ", $sformatf("  [0x%016h] = 0x%08h",
                    result_address + i, word), UVM_MEDIUM)
            end
        end else begin
            `uvm_warning("HOST_SEQ", "result_data[] is empty — driver may have cloned the transaction")
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
        host_configure_dcr_sequence dcr_seq;
        host_launch_kernel_sequence launch_seq;
        host_wait_done_sequence     wait_seq;
        host_read_result_sequence   read_seq;
 
        // FIX 10: m_sequencer null guard
        if (m_sequencer == null)
            `uvm_fatal("HOST_SEQ", "m_sequencer is null — start on env.m_host_agent.m_sequencer")
 
        // Use cfg values if caller left fields at defaults
        if (cfg != null) begin
            if (startup_address == 64'h80000000) startup_address = cfg.startup_addr;
            if (load_address    == 64'h80000000) load_address    = cfg.startup_addr;
            if (timeout_cycles  == 50000)        timeout_cycles  = int'(cfg.test_timeout_cycles);
        end
 
        `uvm_info("HOST_SEQ", $sformatf(
            "Complete test: program=%s entry=0x%016h result=0x%016h timeout=%0d",
            program_path, startup_address, result_address, timeout_cycles), UVM_LOW)
 
        // Step 1: Reset device
        `uvm_info("HOST_SEQ", "Step 1/6: Reset", UVM_LOW)
        reset_seq = host_reset_sequence::type_id::create("reset_seq");
        reset_seq.start(m_sequencer);
 
        // Step 2: Load program into memory
        `uvm_info("HOST_SEQ", "Step 2/6: Load Program", UVM_LOW)
        load_seq = host_load_program_sequence::type_id::create("load_seq");
        load_seq.program_path = program_path;
        load_seq.load_address = load_address;
        load_seq.start(m_sequencer);
 
        // FIX 9: Step 3 — Configure DCR startup address before launch.
        // Without this, DUT fetches from whatever startup_addr was in DCR at reset.
        `uvm_info("HOST_SEQ", "Step 3/6: Configure DCR startup address", UVM_LOW)
        dcr_seq = host_configure_dcr_sequence::type_id::create("dcr_addr0");
        dcr_seq.dcr_address = VX_DCR_BASE_STARTUP_ADDR0;
        dcr_seq.dcr_data    = startup_address[31:0];
        dcr_seq.start(m_sequencer);
 
        dcr_seq = host_configure_dcr_sequence::type_id::create("dcr_addr1");
        dcr_seq.dcr_address = VX_DCR_BASE_STARTUP_ADDR1;
        dcr_seq.dcr_data    = startup_address[63:32];
        dcr_seq.start(m_sequencer);
 
        // Step 4: Launch kernel
        `uvm_info("HOST_SEQ", "Step 4/6: Launch Kernel", UVM_LOW)
        launch_seq = host_launch_kernel_sequence::type_id::create("launch_seq");
        launch_seq.startup_address = startup_address;
        launch_seq.start(m_sequencer);
 
        // Step 5: Wait for completion
        `uvm_info("HOST_SEQ", "Step 5/6: Wait for Completion", UVM_LOW)
        wait_seq = host_wait_done_sequence::type_id::create("wait_seq");
        wait_seq.timeout_cycles = timeout_cycles;
        wait_seq.start(m_sequencer);
 
        // Step 6: Read results
        `uvm_info("HOST_SEQ", "Step 6/6: Read Results", UVM_LOW)
        read_seq = host_read_result_sequence::type_id::create("read_seq");
        read_seq.result_address = result_address;
        read_seq.result_size    = result_size;
        read_seq.start(m_sequencer);
 
        `uvm_info("HOST_SEQ", "Complete test sequence finished", UVM_LOW)
    endtask
    
endclass : host_complete_test_sequence
 
`endif // HOST_SEQUENCES_SV