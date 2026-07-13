# =============================================================================
# coverage_exclude_2CL.do — SUPPLEMENT for the 2CL/2C/4W/4T report only.
# Apply AFTER coverage_exclude.do:
#   vsim -viewcov <2CL_raw> -c -do "do coverage_exclude.do; do coverage_exclude_2CL.do; ..."
#
# coverage_exclude.do carries the g_clusters[0]/g_cores[0] scope paths (the 1CL
# pinned config). At 2CL/2C there are 4 cores (2 clusters x 2 cores) and an L2 in
# each cluster, so this file adds the SAME third-party-IP / config-dead waivers for
# the extra cluster-1 / core-1 instances. Keeping them here (not in the base file)
# means the base file stays clean (0 "had no effect") at 1CL.
# =============================================================================

# --- TCU FP datapath (Berkeley HardFloat third-party IP) for the other 3 cores ---
coverage exclude -scope {/vortex_tb_top/dut/vortex/g_clusters[0]/cluster/g_sockets[0]/socket/g_cores[1]/core/execute/tcu_unit} -recursive -reason EOTH
coverage exclude -scope {/vortex_tb_top/dut/vortex/g_clusters[1]/cluster/g_sockets[0]/socket/g_cores[0]/core/execute/tcu_unit} -recursive -reason EOTH
coverage exclude -scope {/vortex_tb_top/dut/vortex/g_clusters[1]/cluster/g_sockets[0]/socket/g_cores[1]/core/execute/tcu_unit} -recursive -reason EOTH

# --- L2 passthru dead cache interfaces for cluster 1 (L2 still PASSTHRU at 2C) ---
coverage exclude -scope {/vortex_tb_top/dut/vortex/g_clusters[1]/cluster/l2cache/core_bus_cache_if[0]} -recursive -reason EUR
coverage exclude -scope {/vortex_tb_top/dut/vortex/g_clusters[1]/cluster/l2cache/mem_bus_cache_if[0]}  -recursive -reason EUR
