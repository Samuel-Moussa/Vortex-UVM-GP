`ifndef SIMX_WRAPPER_SV
`define SIMX_WRAPPER_SV

module simx_wrapper;

  // Import DPI-C functions
  import "DPI-C" function void simx_init();
  import "DPI-C" function void simx_shutdown();
  import "DPI-C" function void simx_write_dcr(input int addr, input int data);
  import "DPI-C" function void simx_execute_kernel(input longint kernel_addr, input int num_warps, input int num_threads);

  // Export SystemVerilog tasks to be called from C
  // (if needed for callbacks from simx)

endmodule : simx_wrapper

`endif // SIMX_WRAPPER_SV
