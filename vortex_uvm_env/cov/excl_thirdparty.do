coverage exclude -du {fpnew_*}   -reason EOTH
coverage exclude -du {*mvp*}     -reason EOTH
coverage exclude -du cf_math_pkg -reason EOTH
coverage exclude -du lzc         -reason EOTH
coverage exclude -du rr_arb_tree -reason EOTH
coverage exclude -du VX_fpu_fpnew -reason EOTH
coverage exclude -du {VX_tcu_*}  -reason EOTH
coverage exclude -scope {/vortex_tb_top/dut/vortex/g_clusters[0]/cluster/g_sockets[0]/socket/g_cores[0]/core/execute/tcu_unit} -recursive -reason EOTH
