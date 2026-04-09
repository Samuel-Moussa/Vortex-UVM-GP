package simx_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import vortex_config_pkg::*; // Import your config package

    //---------------------------------------------------------
    // DPI Imports
    //---------------------------------------------------------
    import "DPI-C" context function int simx_init(
        input int num_cores,
        input int num_warps,
        input int num_threads
    );

        // --- Raw memory access ---
    import "DPI-C" context function void simx_write_mem(
        input  longint addr,
        input  int     size,
        input  byte    data[]
    );
    import "DPI-C" context function void simx_read_mem(
        input longint addr,
        input int size,
        inout byte data[] // Dynamic array
    );

    import "DPI-C" context function void simx_cleanup();

    // --- Memory loading ---
    import "DPI-C" context function int  simx_load_bin(
        input string filepath,
        input longint load_addr
    );
    import "DPI-C" context function int  simx_load_hex(
        input string filepath
    );
    import "DPI-C" function int  simx_load_hex_at (
        string filepath, longint unsigned base_addr
        );

     // --- DCR configuration ---
    import "DPI-C" context function void simx_dcr_write(
        input int addr,
        input int value
    );

    // --- Execution: post-mortem ---
    import "DPI-C" context function int  simx_run();

    // --- Execution: on-the-fly ---
    import "DPI-C" context function int  simx_step(input int cycles);
    import "DPI-C" context function int  simx_is_done();       // returns 1 when finished
    import "DPI-C" context function int  simx_get_exitcode();  // returns exit code after done

    // --- Optional bootstrap helper ---
    import "DPI-C" context function void simx_init_exit_code_register();

    //---------------------------------------------------------
    // UVM Golden Model Component
    //---------------------------------------------------------
    class simx_golden_model extends uvm_component;
        `uvm_component_utils(simx_golden_model)

        vortex_config cfg;
        
        // Analysis port to send expected transactions to scoreboard
        uvm_analysis_port #(uvm_sequence_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg))
                `uvm_fatal("SIMX", "Config not found!")
        endfunction

        task run_phase(uvm_phase phase);
            byte result_data[];
            int  ret;
            int  exitcode;

            phase.raise_objection(this);  // hold the UVM run phase open

            if (!cfg.simx_enable) begin
                phase.drop_objection(this);
                return;
            end

            // 1. Initialize SimX
            ret = simx_init(cfg.num_cores, cfg.num_warps, cfg.num_threads);
            if (ret != 0) `uvm_fatal("SIMX", "simx_init failed!")

            // 2. Set startup DCR (use 0x001, NOT 0x800)
            simx_dcr_write(32'h001, cfg.startup_addr[31:0]);

            // 3. Load kernel binary
            ret = simx_load_bin(cfg.program_path, cfg.startup_addr);
            if (ret != 0) `uvm_fatal("SIMX", "simx_load_bin failed!")

            // 4. Run to completion (post-mortem mode)
            exitcode = simx_run();
            if (exitcode != 0)
                `uvm_error("SIMX", $sformatf("Non-zero exit code: %0d", exitcode))
            else
                `uvm_info("SIMX", "Program completed with exit code 0", UVM_MEDIUM)

            // 5. Read result memory and send to scoreboard
            result_data = new[cfg.result_size_bytes];
            simx_read_mem(cfg.result_base_addr, cfg.result_size_bytes, result_data);

            // 6. Build transaction and write to analysis port
            // (scoreboard integration — fill in when transaction type is defined)
            // my_txn txn = my_txn::type_id::create("txn");
            // txn.data  = result_data;
            // txn.exitcode = exitcode;
            // ap.write(txn);

            phase.drop_objection(this);  // allow UVM run phase to end
        endtask
        
        function void report_phase(uvm_phase phase);
            simx_cleanup();
        endfunction

    endclass

endpackage