onerror {abort all}
onbreak {abort all}

echo "=== COMPILING UVM ENVIRONMENT ==="

# ------------------------------------------------------------------------------
# Include directories
# ------------------------------------------------------------------------------
set INCDIRS "+incdir+../tb \
             +incdir+../uvm_env \
             +incdir+../uvm_env/agents/axi_agent \
             +incdir+../uvm_env/agents/dcr_agent \
             +incdir+../uvm_env/agents/mem_agent \
             +incdir+../uvm_env/agents/status_agent \
             +incdir+../uvm_env/agents/host_agent \
             +incdir+../uvm_env/sequences \
             +incdir+../uvm_tests"

# ------------------------------------------------------------------------------
# Compile UVM
# ------------------------------------------------------------------------------
vlog -sv -uvm +acc \
     +define+SIMULATION \
     $INCDIRS \
     -f ../vortex_uvm_env/flists/uvm_env.flist

echo "✓ UVM compilation done successfully"
