# Copyright © 2019-2023
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

VORTEX_HOME ?= /home/samuel_ubuntu22/Vortex_UVM_GP/Vortex

CXXFLAGS = -O3 -std=c++11 -Wall -I/usr/include/c++/11 -I/usr/include/x86_64-linux-gnu/c++/11

XLEN ?= 32

TOOLDIR ?= /home/samuel_ubuntu22/tools

OSVERSION ?= ubuntu/focal

INSTALLDIR ?= /home/samuel_ubuntu22/Vortex_UVM_GP/Vortex

LLVM_VORTEX ?= $(TOOLDIR)/llvm-vortex

LIBC_VORTEX ?= $(TOOLDIR)/libc$(XLEN)
LIBCRT_VORTEX ?= $(TOOLDIR)/libcrt$(XLEN)

RISCV_TOOLCHAIN_PATH ?= $(TOOLDIR)/riscv$(XLEN)-gnu-toolchain

RISCV_PREFIX  ?= riscv$(XLEN)-unknown-elf
RISCV_SYSROOT ?= $(RISCV_TOOLCHAIN_PATH)/$(RISCV_PREFIX)

THIRD_PARTY_DIR ?= $(VORTEX_HOME)/third_party

SW_COMMON_DIR ?= $(VORTEX_HOME)/sim/common
