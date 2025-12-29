onerror {abort all}
onbreak {abort all}

echo "=== COMPILING VORTEX RTL ==="
echo "Cleaning work library..."

# If work exists, remove it forcefully
if {[file exists work]} {
    echo "Removing existing work library..."
    catch {file delete -force work}
}

vlib work
vmap work work

echo "✓ Work library created"
echo ""

# ------------------------------------------------------------------------------
set INCDIRS "+incdir+../Vortex/hw \
             +incdir+../Vortex/hw/rtl \
             +incdir+../Vortex/hw/rtl/interfaces \
             +incdir+../Vortex/hw/rtl/core \
             +incdir+../Vortex/hw/rtl/cache \
             +incdir+../Vortex/hw/rtl/mem \
             +incdir+../Vortex/hw/rtl/libs \
             +incdir+../Vortex/hw/rtl/fpu \
             +incdir+../Vortex/hw/rtl/tcu"

vlog -sv +acc \
     +define+SIMULATION \
     +define+USE_AXI_WRAPPER \
     +define+EXT_TCU_ENABLE \
     $INCDIRS \
     -f ../vortex_uvm_env/flists/vortex_rtl.flist

echo "✓ RTL compilation done"
