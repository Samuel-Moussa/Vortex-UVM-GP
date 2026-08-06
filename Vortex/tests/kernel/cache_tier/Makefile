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
$(foreach v,CT_P1 CT_P2 CT_P3 CT_L1_NUM CT_L1_DEN CT_L2_NUM CT_L2_DEN CT_L3_NUM CT_L3_DEN CT_ITERS,\
  $(if $($(v)),$(eval CONFIGS += -D$(v)=$($(v)))))

include ../common.mk
