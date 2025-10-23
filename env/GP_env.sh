#!/bin/bash
# ==========================================
# 🎓 Vortex UVM GP Environment Setup
# ==========================================

# --- Vortex Toolchain ---
if [ -f "$HOME/Vortex_UVM_GP/Vortex/build/ci/toolchain_env.sh" ]; then
    source "$HOME/Vortex_UVM_GP/Vortex/build/ci/toolchain_env.sh"
    echo "[vortex] Toolchain loaded ✅"
else
    echo "[vortex] ⚠️ Toolchain not found, skipping..."
fi

# --- core-v-verif Setup ---
export CV_SIMULATOR="vsim"
export CV_CORE="CV32E40P"
export CV_SW_MARCH="rv32imc_zicsr"
export CV_SW_CC="gcc"
export CV_SW_CFLAGS="-O2 -g -static -mabi=ilp32 -march=$CV_SW_MARCH"

# --- Paths for clarity ---
export CORE_V_VERIF_HOME="$HOME/Vortex_UVM_GP/core-v-verif"
export VORTEX_HOME="$HOME/Vortex_UVM_GP/Vortex"

echo "[core-v-verif] Environment ready ✅"
echo "[GP_env] Vortex + core-v-verif setup loaded successfully 🎯"
