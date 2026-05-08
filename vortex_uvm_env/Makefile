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
#   make clean
#   make help
################################################################################

SHELL := /usr/bin/env bash

RUNNER := scripts/run.sh

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

# ── Feature flags (1 = enable) ────────────────────────────────────────────────
VERBOSE       ?= 0
NO_WAVES      ?= 0
DEBUG_ADDR    ?= 0
NO_TCU        ?= 0

.DEFAULT_GOAL := help

# ── Build the flag string passed to run.sh ────────────────────────────────────
_FLAGS :=
ifneq ($(TEST),)
    _FLAGS += --test=$(TEST)
endif
ifneq ($(PROGRAM),)
    _FLAGS += --program=$(PROGRAM)
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

################################################################################
# Targets
################################################################################

.PHONY: help sim compile sim-only gui clean clean-results

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
