# =============================================================================
# coverage_exclude.do  —  CENTRAL coverage exclusions (Questa 2021.2 syntax)
# Applied ONCE to the merged UCDB. Replaces the old per-test
# coverage_exclude_<vecadd|fpu|warp>.do switching.
#
# Usage (single run or merged db, in coverage view):
#   vsim -viewcov <ucdb> -c -do "do coverage_exclude.do; \
#        coverage report -summary; quit -f"
#
# Every line is a WAIVER with a stated reason — this file is the audit trail.
# Keep it in git.
#
# Questa 2021.2 syntax note: valid exclude forms are
#   -srcfile / -du / -scope / -togglenode / -cvgpath
# There is NO -cvgblk. Cross/coverpoint bin waivers use -cvgpath if ever needed.
# Verify every line matched after a run:
#   grep -c "had no effect" <dryrun.log>     # expect 0
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Third-party cvfpu IP — NOT Vortex DUT. Excluded by DESIGN UNIT (module name),
#    which is what actually works in this Questa build (-srcfile path globs do not
#    match here). Module names confirmed from the load log + coverage -byfile.
# -----------------------------------------------------------------------------
# fpnew core (top, fma, classifier, cast, divsqrt, noncomp, opgroup*, rounding, pkg)
coverage exclude -du {fpnew_*}   -reason EOTH

# div/sqrt mvp units (control, div_sqrt_top, iteration, norm, nrbd_nrsc, preprocess, defs)
coverage exclude -du {*mvp*}     -reason EOTH

# common_cells utility modules (no shared prefix — enumerate)
coverage exclude -du cf_math_pkg -reason EOTH
coverage exclude -du lzc         -reason EOTH
coverage exclude -du rr_arb_tree -reason EOTH

# Vortex-side cvfpu wrapper — try -du; if it misses, it's module VX_fpu_fpnew
coverage exclude -du VX_fpu_fpnew -reason EOTH

# -----------------------------------------------------------------------------
# 2. TCU (tensor core) — FUNCTIONALLY VERIFIED (100% functional cov: tcu_test +
#    tcu_mt issue INST_TCU_WMMA, checked DUT-vs-SimX byte-exact). Its exhaustive
#    bf16 matrix STRUCTURAL coverage is out of scope: the tcu_fp datapath is built
#    from Berkeley HardFloat third-party IP (Vortex/third_party/hardfloat/*:
#    fNToRecFN/recFNToFN/addRecFN/mulRecFN/recFNToRawFN/... — NOT Vortex DUT) and
#    is replicated per matrix element, and it is exercised only by identity-WMMA
#    for functional intent. `-du {VX_tcu_*}` catches the Vortex control modules but
#    NOT the HardFloat submodules (they are named fNToRecFN etc.), so ~5k statements
#    + wide FP toggles leaked into the denominator. Scope-exclude the whole tcu_unit
#    to complete the waiver (config-pinned 1CL/1C path; no-ops harmlessly elsewhere).
# -----------------------------------------------------------------------------
# TCU design units (Vortex control)
coverage exclude -du {VX_tcu_*}       -reason EOTH
# TCU FP datapath incl. Berkeley HardFloat third-party IP (catches the -du leak)
coverage exclude -scope {/vortex_tb_top/dut/vortex/g_clusters[0]/cluster/g_sockets[0]/socket/g_cores[0]/core/execute/tcu_unit} -recursive -reason EOTH

# -----------------------------------------------------------------------------
# 4. Config-DEAD cache-hierarchy interfaces — L2 (per-cluster) and L3 (per-GPU)
#    are instantiated PASSTHRU at this config (L2_ENABLE/L3_ENABLE undefined =>
#    VX_cache_cluster .PASSTHRU(1), Vortex.sv:96 / VX_cluster.sv:107). In passthru
#    mode the cache-side bus interfaces are tied off and NEVER toggle (0% toggle,
#    ~9.8k bins). Structurally unreachable at 1CL/1C — surgically exclude the dead
#    interfaces (NOT the whole l2/l3 scope: the passthru mux path IS exercised and
#    is 82% covered — excluding it would REMOVE hits and lower the number). Verified:
#    +1.75% toggle (removes 9760 miss bins, 0 hits). Config-pinned 1CL/1C paths.
# -----------------------------------------------------------------------------
coverage exclude -scope {/vortex_tb_top/dut/vortex/l3cache/core_bus_cache_if[0]} -recursive -reason EUR
coverage exclude -scope {/vortex_tb_top/dut/vortex/l3cache/mem_bus_cache_if[0]}  -recursive -reason EUR
coverage exclude -scope {/vortex_tb_top/dut/vortex/g_clusters[0]/cluster/l2cache/core_bus_cache_if[0]} -recursive -reason EUR
coverage exclude -scope {/vortex_tb_top/dut/vortex/g_clusters[0]/cluster/l2cache/mem_bus_cache_if[0]}  -recursive -reason EUR

# -----------------------------------------------------------------------------
# 3. Idle-interface functional coverpoints — DO NOT exclude when MERGING.
#    On an AXI run the MEM coverpoints idle (and vice-versa); after an axi+mem
#    merge both are covered, so leaving them in is correct. These lines stay
#    COMMENTED. Uncomment ONLY for a single-run report where you want the idle
#    side dropped from the percentage.
# -----------------------------------------------------------------------------
# coverage exclude -scope /vortex_tb_top/vif -cvgpath {system_cg/mem_usage_cp}     -reason "idle on AXI run"
# coverage exclude -scope /vortex_tb_top/vif -cvgpath {system_cg/system_mem_cross} -reason "idle on AXI run"

# =============================================================================
# End of central exclusions. Add new waivers ABOVE, each with a -reason.
# =============================================================================
