onerror {abort all}
onbreak {abort all}

echo "============================================"
echo " VORTEX RTL + UVM FULL COMPILATION"
echo "============================================"

if {[file exists work]} {
    vdel -all -lib work
}

do compile_rtl.do
do compile_uvm.do

echo "============================================"
echo " ✓ FULL COMPILATION SUCCESSFUL"
echo "============================================"
