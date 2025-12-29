# =============================================================
#   Vortex UVM - General Compilation (Windows QuestaSim)
#   Minimal headers + RTL + DPI used by all agents
# =============================================================

transcript on

# ---------------- CREATE LIBRARIES ---------------------------
if {![file exists "work"]} {
    vlib work
}
vmap work work

# ---------------- SET PATHS ----------------------------------
set VORTEX_ROOT      "D:/vortex_uvm_env/vortex"
set UVM_ENV_ROOT     "D:/vortex_uvm_env/vortex_uvm_env"
set UVM_HOME         $env(UVM_HOME)

# ---------------- FIX 1: COMPILE VH HEADERS AS OPTIONS -------
# vh files MUST NOT be compiled using vlog directly
# They must be included via +incdir only
set INC_VH "+incdir+$VORTEX_ROOT/hw/include"

# ---------------- 1. GLOBAL VORTEX HEADERS/PKG ---------------
vlog -sv $INC_VH \
    $VORTEX_ROOT/hw/include/VX_types.vh \
    $VORTEX_ROOT/hw/include/VX_macros.vh

# ---------------- 2. COMMON RTL NEEDED FOR ALL AGENTS --------
vlog -sv +incdir+$VORTEX_ROOT/hw/rtl/common \
    $VORTEX_ROOT/hw/rtl/common/VX_util.sv \
    $VORTEX_ROOT/hw/rtl/common/VX_priority_encoder.sv \
    $VORTEX_ROOT/hw/rtl/common/VX_fifo.sv \
    $VORTEX_ROOT/hw/rtl/common/VX_shift_register.sv

# ---------------- 3. SIMX DPI PACKAGE ------------------------
vlog -sv +incdir+$VORTEX_ROOT/sim/simx \
    $VORTEX_ROOT/sim/simx/simx_dpi_pkg.sv

# ---------------- 4. UVM PACKAGE ------------------------------
# NOTE: MUST USE -dpiheader AND COMPILE C++ SEPARATELY, not vlog *.cc
vlog -sv $UVM_HOME/src/uvm_pkg.sv

# ---------------- 5. TB INTERFACES ----------------------------
vlog -sv +incdir+$UVM_ENV_ROOT/tb \
    $UVM_ENV_ROOT/tb/vortex_if.sv \
    $UVM_ENV_ROOT/tb/vortex_assertions.sv

# ---------------- 6. UVM CONFIG PKG ---------------------------
vlog -sv +incdir+$UVM_ENV_ROOT/uvm_env \
    $UVM_ENV_ROOT/uvm_env/vortex_config.sv

puts "============================================================="
puts " ✔ Global prerequisite files compiled successfully"
puts " ✔ You may now compile UVM agents individually"
puts "============================================================="

quit -f
