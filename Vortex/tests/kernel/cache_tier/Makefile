ROOT_DIR := $(realpath ../../..)
include $(ROOT_DIR)/config.mk

PROJECT := cache_tier

SRC_DIR := $(VORTEX_HOME)/tests/kernel/$(PROJECT)

SRCS := $(SRC_DIR)/main.cpp

# ── Everything is terminal-controlled; nothing is baked in. ───────────────────
# Phase enables (ALL OFF by default so the default build costs nothing):
#   CT_P1  L1-resident  phase   (span = DCACHE_SIZE   * CT_L1_NUM/CT_L1_DEN)
#   CT_P2  L2-resident  phase   (span = DCACHE_SIZE   * CT_L2_NUM/CT_L2_DEN)
#   CT_P3  L3-resident  phase   (span = L2_CACHE_SIZE * CT_L3_NUM/CT_L3_DEN)
# Span ratios and repetition count are overridable too:
#   CT_L1_NUM/CT_L1_DEN  CT_L2_NUM/CT_L2_DEN  CT_L3_NUM/CT_L3_DEN  CT_ITERS
# Spans are RATIOS of the real geometry (VX_config.h), never absolute byte counts,
# so they stay correct if the cache sizes are reconfigured.
#
#   make CT_P1=1 CT_P2=1                 # L1 + L2 phases
#   make CT_P2=1 CT_P3=1 CT_ITERS=2      # L2 + L3, deeper reuse
# Appended to CONFIGS, which common.mk folds into CFLAGS (line 24) — the project's
# established hook for extra compile defines. Only knobs the user actually set are
# emitted, so the kernel's own `ifndef` defaults stay authoritative otherwise.
# ⚠ `override` IS LOAD-BEARING, DO NOT DROP IT. The UVM env builds every kernel with
# `make -C <kernel> CONFIGS="$want"` (vortex_uvm_env/Makefile:106) — CONFIGS on the
# COMMAND LINE. A command-line variable beats a plain makefile assignment, so a bare
# `CONFIGS +=` here is SILENTLY DISCARDED and the kernel builds with every phase OFF.
# It then runs, stores its results, compares byte-exact against SimX and PASSES —
# having verified nothing (OBS-029: DUT and SimX execute the SAME binary, so a defect
# in the stimulus is common-mode and cancels). Measured 2026-08-16:
#   make -B -n CONFIGS="-DNUM_CORES=2" CT_P1=1  ->  -DNDEBUG -DNUM_CORES=2 -DXLEN_32
#   make -B -n                         CT_P1=1  ->  -DCT_P1=1 -DNDEBUG -DXLEN_32
# `override` makes this assignment win regardless of invocation path.
$(foreach v,CT_P1 CT_P2 CT_P3 CT_L1_NUM CT_L1_DEN CT_L2_NUM CT_L2_DEN CT_L3_NUM CT_L3_DEN CT_ITERS,\
  $(if $($(v)),$(eval override CONFIGS += -D$(v)=$($(v)))))

include ../common.mk
