# GLIBCXX_3.4.29 Library Version Mismatch - RESOLVED ✓

## Issue
```
** Error (suppressible): (vsim-3197) Load of "simx_model.so" failed: 
  /opt/questa_sim-2021.2_1/questasim/gcc-7.4.0-linux_x86_64/lib64/libstdc++.so.6: 
  version `GLIBCXX_3.4.29' not found (required by libramulator.so).
```

**Root Cause:**
- Questa 2021.2 ships GCC 7.4.0 (libstdc++ provides up to GLIBCXX_3.4.25)
- SimX DPI library and dependencies built with GCC 11 (requires GLIBCXX_3.4.29)
- Dynamic linker prioritized Questa's old libstdc++.so.6 when loading dependencies
- libramulator.so (linked by simx_model.so) cannot find GLIBCXX_3.4.29 symbols

---

## Solution

### Part 1: Static Linking (Already in Makefile) ✓
**File:** `vortex_uvm_env/uvm_env/ref_model/Makefile`
```makefile
LDFLAGS := -static-libstdc++ -static-libgcc
```

**Effect:**
- Embeds system libstdc++ directly into simx_model.so
- Verified with: `objdump -p simx_model.so | grep GLIBCXX` → (no output = no dependency)
- simx_model.so is now self-contained

**Limitation:**
- libramulator.so is a precompiled shared library that cannot be linked statically
- It must find the correct libstdc++.so.6 at runtime

### Part 2: Runtime Library Preload (NEW FIX) ✓
**File:** `vortex_uvm_env/scripts/run_vortex_uvm_enhanced.sh` (lines 877-890)
```bash
# Preload correct libstdc++ to resolve GLIBCXX_3.4.29 from ramulator.so dependency
export LD_PRELOAD=/lib/x86_64-linux-gnu/libstdc++.so.6

if [[ $GUI_MODE -eq 1 ]]; then
    vsim vortex_tb_top $SIM_OPTS $DPI_FLAG \
        -do "add wave -r /*; run -all"
else
    vsim -c vortex_tb_top $SIM_OPTS $DPI_FLAG \
        -do "run -all; quit -f" \
        2>&1 | tee "$LOG_FILE"
fi

unset LD_PRELOAD
```

**Effect:**
- Forces dynamic linker to load system libstdc++.so.6 (with GLIBCXX_3.4.29) BEFORE checking Questa's version
- libramulator.so finds correct symbols
- vsim DPI loading succeeds

**Why this works:**
- LD_PRELOAD has highest priority in symbol resolution order
- System libstdc++ (/lib/x86_64-linux-gnu/libstdc++.so.6) has GLIBCXX_3.4.29
- Questa's bundled libstdc++ (/opt/questa_sim-2021.2_1/questasim/gcc-7.4.0-linux_x86_64/lib64/libstdc++.so.6) is skipped

---

## Verification

### DPI Library Status
```bash
$ cd vortex_uvm_env/uvm_env/ref_model
$ make test_lib
```

Output shows:
✓ simx_model.so has no GLIBCXX external dependency (self-contained)
✓ libramulator.so correctly linked as dependency
✓ Runtime workaround documented

### Simulation Test
```bash
$ cd vortex_uvm_env
$ ./scripts/run_vortex_uvm_enhanced.sh \
    --test=vortex_smoke_test \
    --program=uvm_env/agents/host_agent/program_simple.hex \
    --clean
```

Result:
- ✓ No GLIBCXX errors
- ✓ simx_model.so loaded successfully
- ✓ Simulation completed
- ✓ EBREAK detected and parsed

---

## Technical Details

### Binary Dependency Chain
```
vsim
  ├─ simx_model.so (statically linked libstdc++)
  │  └── libramulator.so (dynamically linked, requires GLIBCXX_3.4.29)
  │      └── /lib/x86_64-linux-gnu/libstdc++.so.6 (via LD_PRELOAD)
  │
  └─ /opt/questa_sim-2021.2_1/questasim/uvm-1.2/linux_x86_64/uvm_dpi.so
```

### GCC Version Information
| Component | GCC Version | GLIBCXX Max |
|-----------|-------------|------------|
| System | 11.4.0 | 3.4.29 |
| Questa | 7.4.0 | 3.4.25 |
| simx_model.so | 11 (embedded) | N/A (static) |
| libramulator.so | (unknown) | Requires 3.4.29 |

---

## Prevention for Future Builds

### For Team Members
No action needed! The fix is already deployed:
1. Makefile uses static linking (-static-libstdc++ -static-libgcc)
2. run_vortex_uvm_enhanced.sh sets LD_PRELOAD automatically
3. All tools work out-of-the-box

### If Rebuilding Ramulator
If libramulator.so needs to be rebuilt, use:
```bash
cd Vortex/third_party/ramulator
cmake -DCMAKE_CXX_COMPILER=g++-11 \
      -DCMAKE_CXX_FLAGS="-fPIC -static-libstdc++ -static-libgcc" \
      -DBUILD_SHARED_LIBS=ON .
make
```

This embeds libstdc++ directly into libramulator.so, making the LD_PRELOAD unnecessary.

---

## Files Modified
1. **vortex_uvm_env/scripts/run_vortex_uvm_enhanced.sh**
   - Added LD_PRELOAD environment variable before vsim
   - Scoped to Questa simulator only
   - Properly unset after simulation

2. **vortex_uvm_env/uvm_env/ref_model/Makefile**
   - Updated test_lib target documentation
   - Added Runtime GLIBCXX workaround section
   - Clear instructions for manual workaround if needed

---

## Troubleshooting

### If GLIBCXX Error Still Occurs
Check that LD_PRELOAD is set before running vsim:
```bash
# Manual workaround
export LD_PRELOAD=/lib/x86_64-linux-gnu/libstdc++.so.6
cd vortex_uvm_env
./scripts/run_vortex_uvm_enhanced.sh --test=vortex_smoke_test ...
```

### To Verify LD_PRELOAD Is Working
```bash
# Check what libstdc++ is being used
ldd $(which vsim) | grep libstdc++
# Should show: /lib/x86_64-linux-gnu/libstdc++.so.6 (if LD_PRELOAD active)
```

### To See All Library Dependencies
```bash
cd vortex_uvm_env/uvm_env/ref_model
make test_lib
# Shows complete dependency tree and GLIBCXX symbols
```

---

## Summary
✓ **Fixed:** GLIBCXX_3.4.29 error completely resolved
✓ **Approach:** Two-part solution (static linking + runtime preload)
✓ **Deployment:** Automatic (no manual steps needed)
✓ **Testing:** Verified with smoke test - DPI library loads successfully
✓ **Documentation:** Added to Makefile and scripts for team reference
