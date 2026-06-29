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
PROGRAM       ?= $(KERNEL_32_PROGRAM_DIR)/$(PROGRAM_NAME)/$(PROGRAM_NAME).elf
INTERFACE     ?= axi
CLUSTERS      ?= 1
CORES         ?= 1
WARPS         ?= 4
THREADS       ?= 4
TIMEOUT       ?= 1000000
STARTUP_ADDR  ?= 0x80000000

# ── Regression-program support (kernel_arg_t / MSCRATCH harness) ──────────────
PROGRAM_KIND  ?=
DOGFOOD_TESTID ?=
# Regression programs all build tests/regression/<kind>/kernel.elf
REGRESSION_DIR ?= $(VORTEX_HOME)/tests/regression

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
    # default the binary to the matching kind unless PROGRAM was given explicitly
    PROGRAM ?= $(REGRESSION_DIR)/$(PROGRAM_KIND)/kernel.elf
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
sim: _need-test
	@bash $(RUNNER) $(_FLAGS)

## Compile RTL + UVM only (no simulation)
compile: _need-test
	@bash $(RUNNER) $(_FLAGS) --no-waves --timeout=1

## Simulate only — skips recompilation
sim-only: _need-test
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