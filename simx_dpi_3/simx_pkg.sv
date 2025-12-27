package simx_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import vortex_config_pkg::*; // Import your config package

    //---------------------------------------------------------
    // DPI Imports
    //---------------------------------------------------------
    import "DPI-C" context function int simx_init(
        input string kernel_file,
        input int num_cores,
        input int num_warps,
        input int num_threads
    );

    import "DPI-C" context function int simx_step(input int cycles);

    import "DPI-C" context function void simx_read_memory(
        input longint addr,
        input int size,
        inout byte data[] // Dynamic array
    );

    import "DPI-C" context function void simx_cleanup();

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
            if (!cfg.simx_enable) return;

            // 1. Initialize SimX with values from config object
            int ret = simx_init(
                cfg.program_path,
                cfg.num_cores,
                cfg.num_warps,
                cfg.num_threads
            );
            
            if (ret != 0) `uvm_fatal("SIMX", "Initialization failed!");

            // 2. Run the Model
            // Since SimX 'run()' is blocking and fast, we run it once here.
            void'(simx_step(0)); 

            // 3. Extract Expected Results (Memory Check)
            // Example: Read the "Result Data" area defined in config
            byte result_data[];
            result_data = new[cfg.result_size_bytes];
            
            simx_read_memory(cfg.result_base_addr, cfg.result_size_bytes, result_data);

            // 4. Send to Scoreboard
            // (You need to define what your transaction item looks like)
            // my_txn txn = my_txn::type_id::create("txn");
            // txn.data = result_data;
            // ap.write(txn);
        endtask
        
        function void report_phase(uvm_phase phase);
            simx_cleanup();
        endfunction

    endclass

endpackage