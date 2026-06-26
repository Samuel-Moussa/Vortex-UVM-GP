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
# 2. TCU (tensor core) — compiled in but not exercised until a TCU test exists.
#    Harmless skip if TCU files weren't compiled (--no-tcu). Revisit Stage 2b.
# -----------------------------------------------------------------------------
# TCU design units
coverage exclude -du {VX_tcu_*}       -reason EOTH

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
