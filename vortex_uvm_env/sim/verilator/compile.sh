#!/bin/bash

# Set up environment
export VERILATOR_ROOT=/path/to/verilator
export PATH=$VERILATOR_ROOT/bin:$PATH

# Clean up previous build
rm -rf obj_dir

# Verilate the design
verilator -Wall --cc --trace --exe --build -j 0 \
          -I/home/ubuntu/vortex-2.2/hw/rtl \
          -I/home/ubuntu/vortex_uvm_env/tb \
          -I/home/ubuntu/vortex_uvm_env/uvm_env \
          /home/ubuntu/vortex_uvm_env/tb/vortex_tb_top.sv \
          /home/ubuntu/vortex_uvm_env/sim/verilator/sim_main.cpp \
          /home/ubuntu/vortex_uvm_env/uvm_env/ref_model/simx_dpi.cpp \
          --top-module vortex_tb_top
