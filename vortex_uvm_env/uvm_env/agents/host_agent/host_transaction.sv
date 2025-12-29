////////////////////////////////////////////////////////////////////////////////
// File: host_transaction.sv
// Description: Host Transaction for High-Level Kernel Operations
//
// This transaction represents host-level operations that control the Vortex
// GPU. The host agent orchestrates multiple low-level agents (mem, dcr, status)
// to perform complex operations.
//
// Transaction Types:
//   - HOST_RESET:         Reset the device
//   - HOST_LOAD_PROGRAM:  Load program into memory (via mem_agent)
//   - HOST_CONFIGURE_DCR: Write DCR registers (via dcr_agent)
//   - HOST_LAUNCH_KERNEL: Start kernel execution (via dcr_agent)
//   - HOST_WAIT_DONE:     Wait for completion (via status_agent)
//   - HOST_READ_RESULT:   Read results from memory (via mem_agent)
//
// Key Design:
//   - Transaction is pure data (no interface access)
//   - Driver uses clocking blocks: mem_vif.master_cb, dcr_vif.master_cb
//   - Monitor observes: dcr_vif.monitor_cb, status_vif.monitor_cb
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef HOST_TRANSACTION_SV
`define HOST_TRANSACTION_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import host_agent_pkg::*;


class host_transaction extends uvm_sequence_item;
    
    //==========================================================================
    // Transaction Type Enumeration
    //==========================================================================
    typedef enum {
        HOST_RESET,          // Reset the device
        HOST_LOAD_PROGRAM,   // Load program into memory (uses mem_vif.master_cb)
        HOST_CONFIGURE_DCR,  // Write to DCR registers (uses dcr_vif.master_cb)
        HOST_LAUNCH_KERNEL,  // Start kernel execution (uses dcr_vif.master_cb)
        HOST_WAIT_DONE,      // Wait for completion (uses status_vif.monitor_cb)
        HOST_READ_RESULT     // Read results from memory (uses mem_vif.master_cb)
    } host_op_type_e;
    
    //==========================================================================
    // Transaction Fields
    //==========================================================================
    
    // Operation type
    rand host_op_type_e op_type;
    
    //--------------------------------------------------------------------------
    // Program Loading Fields (executed via mem_vif.master_cb)
    //--------------------------------------------------------------------------
    string      program_path;        // Path to program file (hex/elf/bin)
    bit [63:0]  load_address;        // Memory address to load program
    bit [31:0]  program_size;        // Program size in bytes
    byte        program_data[];      // Program binary data
    
    //--------------------------------------------------------------------------
    // DCR Configuration Fields (executed via dcr_vif.master_cb)
    //--------------------------------------------------------------------------
    bit [31:0]  dcr_address;         // DCR register address
    bit [31:0]  dcr_data;            // DCR register data
    
    //--------------------------------------------------------------------------
    // Kernel Launch Parameters (executed via dcr_vif.master_cb)
    //--------------------------------------------------------------------------
    bit [63:0]  startup_address;     // Kernel entry point (PC)
    bit [31:0]  num_cores;           // Number of cores to use
    bit [31:0]  num_warps;           // Number of warps per core
    bit [31:0]  num_threads;         // Number of threads per warp
    bit [31:0]  argc;                // Argument count
    bit [63:0]  argv_ptr;            // Pointer to argument array
    
    //--------------------------------------------------------------------------
    // Synchronization Fields (monitored via status_vif.monitor_cb)
    //--------------------------------------------------------------------------
    int         timeout_cycles;      // Timeout for wait operations
    bit         completion_flag;     // Set when operation completes
    
    //--------------------------------------------------------------------------
    // Result Reading Fields (executed via mem_vif.master_cb)
    //--------------------------------------------------------------------------
    bit [63:0]  result_address;      // Memory address to read results
    bit [31:0]  result_size;         // Result size in bytes
    byte        result_data[];       // Result data buffer
    
    //--------------------------------------------------------------------------
    // Timing Information
    //--------------------------------------------------------------------------
    time        start_time;          // Operation start time
    time        end_time;            // Operation end time
    
    //==========================================================================
    // Constraints
    //==========================================================================
    
    // Reasonable timeout values
    constraint reasonable_timeout_c {
        timeout_cycles inside {[1000:100000]};
    }
    
    // Valid startup address (word-aligned)
    constraint valid_startup_addr_c {
        startup_address[1:0] == 2'b00;  // Word-aligned
    }
    
    // Valid core/warp/thread configuration
    constraint valid_config_c {
        num_cores inside {[1:8]};
        num_warps inside {[1:8]};
        num_threads inside {[1:4]};
    }
    
    // Aligned memory addresses
    constraint aligned_addresses_c {
        load_address[1:0] == 2'b00;     // Word-aligned
        result_address[1:0] == 2'b00;   // Word-aligned
    }
    
    //==========================================================================
    // UVM Automation Macros
    //==========================================================================
    `uvm_object_utils_begin(host_transaction)
        `uvm_field_enum(host_op_type_e, op_type, UVM_ALL_ON)
        `uvm_field_string(program_path, UVM_ALL_ON)
        `uvm_field_int(load_address, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(program_size, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(startup_address, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(num_cores, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(num_warps, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(num_threads, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(timeout_cycles, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(completion_flag, UVM_ALL_ON)
    `uvm_object_utils_end
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "host_transaction");
        super.new(name);
        
        // Default values
        timeout_cycles = 10000;
        completion_flag = 0;
        num_cores = 1;
        num_warps = 4;
        num_threads = 4;
        startup_address = 64'h80000000;
    endfunction
    
    //==========================================================================
    // Load Program from File
    // Reads binary data from file into program_data array
    //==========================================================================
    function bit load_program_from_file(string file_path);
        int fd;
        byte temp_byte;
        int bytes_read = 0;
        
        program_path = file_path;
        
        // Open file in binary read mode
        fd = $fopen(file_path, "rb");
        if (fd == 0) begin
            `uvm_error("HOST_TRANS", $sformatf("Cannot open file: %s", file_path))
            return 0;
        end
        
        // Get file size
        $fseek(fd, 0, 2);  // Seek to end
        program_size = $ftell(fd);
        $fseek(fd, 0, 0);  // Seek to start
        
        // Allocate buffer
        program_data = new[program_size];
        
        // Read file byte by byte
        for (int i = 0; i < program_size; i++) begin
            if ($fread(temp_byte, fd) == 1) begin
                program_data[i] = temp_byte;
                bytes_read++;
            end else begin
                break;
            end
        end
        
        $fclose(fd);
        
        `uvm_info("HOST_TRANS", $sformatf("Loaded %0d bytes from %s",
            bytes_read, file_path), UVM_MEDIUM)
        
        return (bytes_read == program_size);
    endfunction
    
    //==========================================================================
    // Calculate Execution Time in Cycles
    // Assumes 10ns clock period (100MHz)
    //==========================================================================
    function int get_execution_cycles();
        if (end_time > start_time)
            return (end_time - start_time) / 10;
        else
            return 0;
    endfunction
    
    //==========================================================================
    // Convert to String (for debugging and logging)
    //==========================================================================
    virtual function string convert2string();
        string s;
        
        s = super.convert2string();
        s = {s, $sformatf("\n┌─ Host Transaction ───────────────")};
        s = {s, $sformatf("\n│ Operation: %s", op_type.name())};
        
        case (op_type)
            HOST_LOAD_PROGRAM: begin
                s = {s, $sformatf("\n│ Program:       %s", program_path)};
                s = {s, $sformatf("\n│ Load Address:  0x%016h", load_address)};
                s = {s, $sformatf("\n│ Size:          %0d bytes", program_size)};
                s = {s, "\n│ [Executed via mem_vif.master_cb]"};
            end
            
            HOST_CONFIGURE_DCR: begin
                s = {s, $sformatf("\n│ DCR Address:   0x%08h", dcr_address)};
                s = {s, $sformatf("\n│ DCR Data:      0x%08h", dcr_data)};
                s = {s, "\n│ [Executed via dcr_vif.master_cb]"};
            end
            
            HOST_LAUNCH_KERNEL: begin
                s = {s, $sformatf("\n│ Startup Addr:  0x%016h", startup_address)};
                s = {s, $sformatf("\n│ Configuration: %0d cores, %0d warps, %0d threads",
                    num_cores, num_warps, num_threads)};
                s = {s, "\n│ [Executed via dcr_vif.master_cb]"};
            end
            
            HOST_WAIT_DONE: begin
                s = {s, $sformatf("\n│ Timeout:       %0d cycles", timeout_cycles)};
                s = {s, $sformatf("\n│ Completed:     %s",
                    completion_flag ? "YES" : "NO")};
                if (completion_flag) begin
                    s = {s, $sformatf("\n│ Exec Time:     %0d cycles",
                        get_execution_cycles())};
                end
                s = {s, "\n│ [Monitored via status_vif.monitor_cb]"};
            end
            
            HOST_READ_RESULT: begin
                s = {s, $sformatf("\n│ Result Addr:   0x%016h", result_address)};
                s = {s, $sformatf("\n│ Result Size:   %0d bytes", result_size)};
                s = {s, "\n│ [Executed via mem_vif.master_cb]"};
            end
            
            HOST_RESET: begin
                s = {s, "\n│ [Reset device]"};
            end
        endcase
        
        s = {s, "\n└──────────────────────────────────"};
        
        return s;
    endfunction
    
    //==========================================================================
    // Compare Transactions (for scoreboard)
    //==========================================================================
    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        host_transaction rhs_;
        
        if (!$cast(rhs_, rhs)) begin
            `uvm_error("HOST_TRANS", "Cast failed in do_compare")
            return 0;
        end
        
        return (
            super.do_compare(rhs, comparer) &&
            (op_type == rhs_.op_type) &&
            (startup_address == rhs_.startup_address) &&
            (num_cores == rhs_.num_cores)
        );
    endfunction
    
    //==========================================================================
    // Deep Copy
    //==========================================================================
    virtual function void do_copy(uvm_object rhs);
        host_transaction rhs_;
        
        if (!$cast(rhs_, rhs)) begin
            `uvm_error("HOST_TRANS", "Cast failed in do_copy")
            return;
        end
        
        super.do_copy(rhs);
        
        // Copy all fields
        op_type = rhs_.op_type;
        program_path = rhs_.program_path;
        load_address = rhs_.load_address;
        program_size = rhs_.program_size;
        
        // Deep copy dynamic arrays
        if (rhs_.program_data.size() > 0) begin
            program_data = new[rhs_.program_data.size()];
            program_data = rhs_.program_data;
        end
        
        dcr_address = rhs_.dcr_address;
        dcr_data = rhs_.dcr_data;
        startup_address = rhs_.startup_address;
        num_cores = rhs_.num_cores;
        num_warps = rhs_.num_warps;
        num_threads = rhs_.num_threads;
        argc = rhs_.argc;
        argv_ptr = rhs_.argv_ptr;
        timeout_cycles = rhs_.timeout_cycles;
        completion_flag = rhs_.completion_flag;
        result_address = rhs_.result_address;
        result_size = rhs_.result_size;
        
        if (rhs_.result_data.size() > 0) begin
            result_data = new[rhs_.result_data.size()];
            result_data = rhs_.result_data;
        end
        
        start_time = rhs_.start_time;
        end_time = rhs_.end_time;
    endfunction
    
endclass : host_transaction

`endif // HOST_TRANSACTION_SV
