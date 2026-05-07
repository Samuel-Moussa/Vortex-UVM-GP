SHELL := /bin/bash

# --- Color Codes ---
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[1;33m
BLUE   := \033[0;34m
CYAN   := \033[0;36m
NC     := \033[0m

# --- Inputs ---
TEST ?= vortex_sanity_test
PROGRAM ?=
INTERFACE ?= axi
CLUSTERS ?= 1
CORES ?= 1
WARPS ?= 4
THREADS ?= 4
XLEN ?= 32
NO_TCU ?= 0
NO_WAVES ?= 0
VERBOSE ?= 0
CLEAN ?= 0
TIMEOUT ?= 1000000
DEBUG_ADDR ?= 0

# --- Environment Variables (from .bashrc) ---
MAKEFILE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
VORTEX_UVM_HOME ?= $(abspath $(MAKEFILE_DIR)/..)
VORTEX_HOME ?= $(abspath $(VORTEX_UVM_HOME)/..)

QUESTA_HOME ?= $(QUESTASIM_HOME)
RISCV_TOOLCHAIN_PATH ?= /opt/riscv
UVM_HOME ?= $(QUESTA_HOME)/verilog_src/uvm-1.2/src
UVM_DPI_LIB ?= $(QUESTA_HOME)/uvm-1.2/linux_x86_64/uvm_dpi

# --- Results Directory Setup ---
RESULTS_BASE := $(VORTEX_UVM_HOME)/results
RESULTS_DATE := $(shell date +"%Y%m%d")
RESULTS_TIME := $(shell date +"%H%M%S")
RUN_DIR := $(RESULTS_BASE)/$(RESULTS_DATE)/run_$(RESULTS_TIME)_$(TEST)

setup_dirs:
	@mkdir -p $(RUN_DIR)/logs $(RUN_DIR)/waves $(RUN_DIR)/reports $(RUN_DIR)/programs
	@ln -sfn $(RUN_DIR) $(RESULTS_BASE)/latest
	@echo -e "================================================================================" > $(RUN_DIR)/reports/config.txt
	@echo -e "Test Run Configuration" >> $(RUN_DIR)/reports/config.txt
	@echo -e "Test: $(TEST), Program: $(PROGRAM), Interface: $(INTERFACE)" >> $(RUN_DIR)/reports/config.txt
	@echo -e "Clusters: $(CLUSTERS), Cores: $(CORES), Warps: $(WARPS), Threads: $(THREADS)" >> $(RUN_DIR)/reports/config.txt
	@echo -e "================================================================================" >> $(RUN_DIR)/reports/config.txt