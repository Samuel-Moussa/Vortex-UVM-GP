################################################################################
# Makefile — Vortex UVM Verification
# Top-level configuration and orchestration.
# All variables here are exported to scripts/run.sh and its sub-scripts.
#
# Usage:
#   make sim       TEST=vortex_smoke_test PROGRAM=vecadd
#   make gui       TEST=vortex_smoke_test PROGRAM=rv32ui-p-add
#   make sim-only  TEST=vortex_smoke_test PROGRAM=vecadd     # skip recompile
#   make compile   TEST=vortex_smoke_test                    # compile only
#   make cov-fresh                                           # clear coverage staging
#   make cov-merge                                           # merge staged UCDBs -> report
#   make cov-list                                            # show staged UCDBs
#   make clean
#   make help
################################################################################

SHELL := /usr/bin/env bash

RUNNER     := scripts/run.sh
COV_MERGE  := scripts/merge_coverage.sh

# ── Optional per-developer local overrides (not tracked by git) ───────────────
-include local.mk

# ── GPU / Test configuration (override on command line) ───────────────────────
TEST          ?=
KERNEL_32_PROGRAM_DIR ?= $(VORTEX_HOME)/tests/kernel
PROGRAM_NAME  ?=
# PROGRAM is defaulted below, AFTER PROGRAM_KIND is known (regression vs kernel).
INTERFACE     ?= axi
CLUSTERS      ?= 1
CORES         ?= 1
WARPS         ?= 4
THREADS       ?= 4
TIMEOUT       ?= 1000000
STARTUP_ADDR  ?= 0x80000000

# ── Cache hierarchy (defaults mirror the RTL's own defaults) ──────────────────
# L2/L3 are the OPTIONAL levels and are PASSTHRU (pure bypass, no cache array)
# unless enabled — see VX_cache_wrap.sv:160. Example:
#   make sim TEST=... PROGRAM_NAME=... CLUSTERS=2 CORES=2 L2=1 L3=1
L2            ?= 0
L3            ?= 0
ICACHE        ?= 1
DCACHE        ?= 1

# ── Regression-program support (kernel_arg_t / MSCRATCH harness) ──────────────
PROGRAM_KIND  ?=
DOGFOOD_TESTID ?=
# Regression programs all build tests/regression/<kind>/kernel.elf
REGRESSION_DIR ?= $(VORTEX_HOME)/tests/regression

# ── Default PROGRAM (an explicit PROGRAM= on the cmd line still wins via ?=) ──
# A regression kind maps to tests/regression/<kind>/kernel.elf; otherwise fall
# back to the kernel program path. Done here so PROGRAM_KIND is already known.
ifneq ($(PROGRAM_KIND),)
    PROGRAM   ?= $(REGRESSION_DIR)/$(PROGRAM_KIND)/kernel.elf
else
    PROGRAM   ?= $(KERNEL_32_PROGRAM_DIR)/$(PROGRAM_NAME)/$(PROGRAM_NAME).elf
endif

# ── PER-CONFIG KERNEL BUILD (OBS-028 / OBS-029) ───────────────────────────────
# Kernel programs read NUM_CLUSTERS/NUM_CORES/NUM_WARPS/NUM_THREADS from
# Vortex/hw/VX_config.h, which HARDCODES 1/1/4/4. `common.mk:24` already honours
# $(CONFIGS) — but nothing ever passed it, and PROGRAM below points at a PREBUILT
# .elf, so every kernel was compiled for a 1-cluster/1-core machine no matter what
# you typed on the command line. Measured consequence: wide_stress computed
# TOTAL = NUM_CLUSTERS*NUM_CORES*NUM_WARPS*NUM_THREADS = 16 and ran with
# per_cluster_busy=01 for its entire ~1.4M-cycle run at 2CL — three quarters of the
# machine idle, in a kernel whose own comment says "Multi-core aware".
#
# Grid sizing is now queried at RUNTIME in the scaled kernels (drift-proof), but
# some uses are STRUCTURAL and can only be compile-time:
#   * tcu_*: `wmma_context<NUM_THREADS,...>` is a TEMPLATE argument — the tile
#     geometry is part of the type;
#   * several kernels size STATIC ARRAYS from the macros.
# Those are only correct if the program is rebuilt when the config changes.
#
# ⚠ This matters more than a coverage detail. Per OBS-029, a kernel compiled for
# the wrong geometry CANNOT be caught by any checker here: DUT and SimX execute the
# SAME binary, so both are wrong identically and every compare passes. Getting the
# build right is the only defence.
#
# The stamp records the flags the .elf was ACTUALLY built with — the same trick as
# Vortex/sim/simx/simx_config.stamp (I3) — so an unchanged config costs nothing and
# a changed one can never be silently skipped.
# KERNEL_EXTRA_CONFIGS: per-program compile defines (e.g. cache_tier's phase enables).
# It MUST go through KERNEL_CONFIGS rather than being passed to the kernel Makefile as
# a separate variable, for two reasons measured on 2026-08-16:
#  1. the rule below invokes the kernel Makefile with CONFIGS="$$want" ON THE COMMAND
#     LINE, and a command-line variable overrides a makefile's `CONFIGS +=`. So
#     `make ... CT_P1=1` through this path SILENTLY DROPS the flag — the kernel builds
#     with every phase off, then runs and passes while verifying nothing (OBS-029).
#     Proven: `-DCT_P1=1` present without a command-line CONFIGS, absent with one.
#  2. the stamp records $(KERNEL_CONFIGS), so folding the extras in here is also what
#     makes a phase change force a rebuild instead of reusing a stale .elf.
KERNEL_CONFIGS := -DNUM_CLUSTERS=$(CLUSTERS) -DNUM_CORES=$(CORES) -DNUM_WARPS=$(WARPS) -DNUM_THREADS=$(THREADS) $(KERNEL_EXTRA_CONFIGS)
ifneq ($(PROGRAM_KIND),)
    KERNEL_SRC_DIR := $(REGRESSION_DIR)/$(PROGRAM_KIND)
    KERNEL_ELF     := $(REGRESSION_DIR)/$(PROGRAM_KIND)/kernel.elf
else
    KERNEL_SRC_DIR := $(KERNEL_32_PROGRAM_DIR)/$(PROGRAM_NAME)
    KERNEL_ELF     := $(KERNEL_32_PROGRAM_DIR)/$(PROGRAM_NAME)/$(PROGRAM_NAME).elf
endif
KERNEL_STAMP := $(KERNEL_SRC_DIR)/.kernel_config.stamp

## Rebuild the program for the requested config, but only when it actually changed.
.PHONY: kernel-config
kernel-config:
	@if [ -n "$(PROGRAM_NAME)$(PROGRAM_KIND)" ] && [ -f "$(KERNEL_SRC_DIR)/Makefile" ]; then \
	  want='$(KERNEL_CONFIGS)'; \
	  have=`cat '$(KERNEL_STAMP)' 2>/dev/null || echo ''`; \
	  if [ "$$want" != "$$have" ] || [ ! -f '$(KERNEL_ELF)' ]; then \
	    echo "[kernel-config] $(notdir $(KERNEL_SRC_DIR)): rebuilding for $$want"; \
	    $(MAKE) -s -C '$(KERNEL_SRC_DIR)' clean >/dev/null 2>&1 || true; \
	    if $(MAKE) -s -C '$(KERNEL_SRC_DIR)' CONFIGS="$$want"; then \
	      printf '%s' "$$want" > '$(KERNEL_STAMP)'; \
	    else \
	      echo "[kernel-config] ERROR: $(notdir $(KERNEL_SRC_DIR)) FAILED to build for $$want."; \
	      echo "[kernel-config] Refusing to run a program built for a DIFFERENT config —"; \
	      echo "[kernel-config] DUT and SimX would both execute it and agree on the same"; \
	      echo "[kernel-config] wrong answer, so no checker here could detect it (OBS-029)."; \
	      rm -f '$(KERNEL_STAMP)'; exit 1; \
	    fi; \
	  fi; \
	fi

## Force a rebuild of the current program regardless of the stamp.
.PHONY: kernel-rebuild
kernel-rebuild:
	@rm -f '$(KERNEL_STAMP)'
	@$(MAKE) --no-print-directory kernel-config

# ── Coverage merge selection (override on command line) ───────────────────────
# RUNS  = explicit run dirs under results/ to stage, space-separated, e.g.
#         make cov-merge RUNS="20260620/run_A_kernel_launch_test 20260620/run_B_..."
# LAST  = if RUNS empty, stage the N most-recent run_*$(TEST_GLOB) dirs (default 4)
RUNS          ?=
LAST          ?= 4
TEST_GLOB     ?= kernel_launch_test

COV_REPORT      ?= 0
COV_REPORT_FLAG := $(if $(filter 1,$(COV_REPORT)),--cov-report,)

# ── Feature flags (1 = enable) ────────────────────────────────────────────────
VERBOSE       ?= 0
NO_WAVES      ?= 0
DEBUG_ADDR    ?= 0
NO_TCU        ?= 0
STRESS_ITER   ?= 1

.DEFAULT_GOAL := help

# ── Build the flag string passed to run.sh ────────────────────────────────────
_FLAGS :=
ifneq ($(TEST),)
    _FLAGS += --test=$(TEST)
endif
ifneq ($(PROGRAM),)
    _FLAGS += --program=$(PROGRAM)
endif
ifneq ($(PROGRAM_KIND),)
    _FLAGS  += --program-kind=$(PROGRAM_KIND)
endif
ifneq ($(DOGFOOD_TESTID),)
    _FLAGS += --dogfood-testid=$(DOGFOOD_TESTID)
endif
_FLAGS += --interface=$(INTERFACE)
_FLAGS += --clusters=$(CLUSTERS)
_FLAGS += --cores=$(CORES)
_FLAGS += --warps=$(WARPS)
_FLAGS += --threads=$(THREADS)
_FLAGS += --timeout=$(TIMEOUT)
_FLAGS += --startup-addr=$(STARTUP_ADDR)
_FLAGS += --l2=$(L2)
_FLAGS += --l3=$(L3)
_FLAGS += --icache=$(ICACHE)
_FLAGS += --dcache=$(DCACHE)
ifeq ($(VERBOSE),1)
    _FLAGS += --verbose
endif
ifeq ($(NO_WAVES),1)
    _FLAGS += --no-waves
endif
ifeq ($(DEBUG_ADDR),1)
    _FLAGS += --debug-addr
endif
ifeq ($(NO_TCU),1)
    _FLAGS += --no-tcu
endif
ifneq ($(STRESS_ITER),1)
    _FLAGS += --stress-iter=$(STRESS_ITER)
endif

################################################################################
# Targets
################################################################################

.PHONY: help sim compile sim-only gui clean clean-results \
        cov-fresh cov-merge cov-list

help:
	@bash $(RUNNER) --help

## Full flow: compile + simulate
sim: _need-test kernel-config
	@bash $(RUNNER) $(_FLAGS)

## Compile RTL + UVM only (no simulation)
# The 1-cycle smoke sim has no meaningful test verdict: it exits 3 (UNKNOWN) or 2
# (the TB's own "TIMEOUT after 1 cycles!" $error counts as an RTL error line).
# Tolerate exactly those two. Real compile/prepare failures exit earlier with
# other codes (run.sh exit 1 paths / crash codes) and still fail this target.
compile: _need-test kernel-config
	@bash $(RUNNER) $(_FLAGS) --no-waves --timeout=1 || { rc=$$?; [ $$rc -eq 2 ] || [ $$rc -eq 3 ]; }

## Simulate only — skips recompilation
sim-only: _need-test kernel-config
	@bash $(RUNNER) $(_FLAGS) --no-compile

## Open Questa GUI with waveforms
gui: _need-test
	@bash $(RUNNER) $(_FLAGS) --gui

## Coverage: clear the staging set to start a clean report
cov-fresh:
	@bash $(COV_MERGE) --fresh

## Coverage: show what is currently staged
cov-list:
	@bash $(COV_MERGE) --list

## Coverage: stage selected runs (RUNS=... or newest LAST=N matching TEST_GLOB),
## then merge into one report. cvfpu/third-party waived via coverage_exclude.do.
cov-merge:
	@bash $(COV_MERGE)

## Remove ModelSim work library
clean:
	@rm -rf flists/work && echo "work/ removed."

## Remove all results
clean-results:
	@rm -rf results/ && echo "results/ removed."

## Guard: TEST must be set
.PHONY: _need-test
_need-test:
ifeq ($(TEST),)
	$(error TEST is required. Example: make sim TEST=vortex_smoke_test PROGRAM=vecadd)
endif