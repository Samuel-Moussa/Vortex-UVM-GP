# simx_dpi
dpi-c is bridge between simx (Golden model) which is behavioral model in C++  and RTL in systemVerilog

1. The Problem and the Importance of DPI-C
  The Problem: Your team is building a UVM environment for the Vortex GPGPU. To verify that the RTL is correct, you need a Golden Model (an "oracle") that knows exactly what the results   should be.
  Vortex already has SimX, a high-performance C++ behavioral model. However, SystemVerilog (UVM) and C++ (SimX) cannot "talk" to each other directly because they run in different memory spaces and use different languages.
  The Importance of DPI-C (Direct Programming Interface): DPI-C is the standard interface that allows SystemVerilog to call C functions as if they were native tasks.
  Efficiency: It allows you to reuse the existing SimX code instead of rewriting the entire Vortex logic in SystemVerilog.
  Synchronization: It allows the UVM environment to control the Golden Model (load memory, step cycles, read registers) in perfect sync with the RTL simulation.

2. The Solution: Files and Architecture
  We created a bridge architecture that connects your UVM configuration to the SimX internals.
Key Files Created:
  simx_dpi.cpp (The Bridge): * This is the C++ wrapper. It contains extern "C" functions that SystemVerilog can see.
  It manages the global pointers for the vortex::Processor and vortex::RAM.
  Final Version Logic: It uses dynamic arguments for num_cores, num_warps, etc., so that the C++ model matches your randomized UVM config. It initializes a large RAM (4GB) to avoid memory range errors.
  vortex_config.sv: * Your UVM configuration object. It stores the architectural parameters (threads, warps, etc.) that are passed to the DPI functions during the build_phase.
  test_top.sv (The Testbench):
  A top-level module used to verify the connection. It imports the DPI functions and uses a "backdoor" approach to write data into SimX memory at address 0x80000000 without needing external binary files.

3. The Shared Object (.so) and UVM Flow
  What is the .so file? The simx_model.so is a Shared Object (a Linux library). It is the compiled binary version of your simx_dpi.cpp combined with all the SimX logic, Softfloat, and Ramulator dependencies.
  Importance: The simulator (Questasim) cannot read .cpp files. It only knows how to load a pre-compiled .so library into its process memory.
Using it in the UVM Flow:
  Compilation: You compile your SV code with vlog and your C++ code into the .so using g++.
  Loading: In your vsim command, you use -sv_lib simx_model.
  UVM Component: Inside your UVM Reference Model or Scoreboard, you simply call the imported functions (like simx_init) to move data into the Golden Model for comparison against RTL.

4. Problems Faced and Solutions
  During the implementation on WSL/Ubuntu with Questasim 2021, we solved four major "roadblocks":
    Missing g++ and Headers: * Problem: WSL didn't have a compiler, and svdpi.h wasn't found.
      Solution: Installed build-essential and added the Questasim /include directory to the Makefile.
  GLIBCXX Version Mismatch:
    Problem: Questasim 2021 includes an old version of the C++ library, but your WSL compiler is modern. This caused GLIBCXX_3.4.29 not found errors.
    Solution: Used export LD_PRELOAD=/lib/x86_64-linux-gnu/libstdc++.so.6 to force the simulator to use the modern system library.
  Memory Out-of-Range (SIGABRT):
    Problem: SimX threw a C++ exception because we tried to write to address 0x80000000 while the RAM was only initialized for 16MB.
    Solution: Updated simx_init in the C++ code to initialize a 4GB RAM range (0xFFFFFFFF).
  Incomplete Types (ifstream):
    Problem: Missing C++ standard headers.
    Solution: Added #include <fstream> and eventually shifted to a direct SV-to-Memory transfer to simplify the testing flow.

   
