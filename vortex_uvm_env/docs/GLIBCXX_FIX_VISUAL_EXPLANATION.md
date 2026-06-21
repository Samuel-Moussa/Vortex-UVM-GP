# Visual Explanation: GLIBCXX_3.4.29 Fix

## Problem Visualization (Before Fix)

```
┌─────────────────────────────────────────────────────────────┐
│                        vsim (Questa 2021.2)                 │
│                    (uses GCC 7.4.0 libstdc++)               │
└──────────────────────┬──────────────────────────────────────┘
                       │
        ┌──────────────┴──────────────┐
        │                             │
    ┌───▼──────────────────┐   ┌─────▼──────────┐
    │  simx_model.so       │   │ uvm_dpi.so     │
    │  (built with GCC 11) │   │ (Questa)       │
    └───┬──────────────────┘   └────────────────┘
        │
        └──► libramulator.so (requires GLIBCXX_3.4.29)
             │
             └──► Looks for libstdc++.so.6
                  │
                  └──► /opt/questa_sim-2021.2_1/questasim/gcc-7.4.0-linux_x86_64/lib64/libstdc++.so.6
                       │
                       └──► GLIBCXX_3.4.25 MAX ✗ FAILS
                            (doesn't have GLIBCXX_3.4.29)

ERROR: vsim-3197 Load of "simx_model.so" failed:
       version `GLIBCXX_3.4.29' not found
```

## Solution Visualization (After Fix)

```
STEP 1: Set LD_PRELOAD (run_vortex_uvm_enhanced.sh)
┌──────────────────────────────────────────────┐
│ export LD_PRELOAD=/lib/x86_64-linux-gnu/    │
│         libstdc++.so.6                        │
└──────────────────────────────────────────────┘
           │
           └──► Highest priority in symbol resolution
                (checked BEFORE system/Questa libraries)


STEP 2: Dynamic Loader Resolution Order
┌──────────────────────────────────────────────────────────┐
│ 1. LD_PRELOAD libs          ← /lib/x86_64.../libstdc++   │ ✓
│ 2. LD_LIBRARY_PATH libs                                   │
│ 3. /etc/ld.so.cache                                       │
│ 4. System default paths                                   │
│ 5. Questa's bundled libs                                  │ ✗ (skipped)
└──────────────────────────────────────────────────────────┘


STEP 3: Library Loading Chain
┌─────────────────────────────────────────────────────────────┐
│                        vsim                                 │
│              (uses GCC 7.4.0 libstdc++)                    │
└──────────────────────┬──────────────────────────────────────┘
                       │
        ┌──────────────┴──────────────┐
        │                             │
    ┌───▼──────────────────┐   ┌─────▼──────────┐
    │  simx_model.so       │   │ uvm_dpi.so     │
    │  (static libstdc++)  │   │ (Questa)       │
    └───┬──────────────────┘   └────────────────┘
        │
        └──► libramulator.so (requires GLIBCXX_3.4.29)
             │
             └──► Looks for libstdc++.so.6
                  │
                  └──► LD_PRELOAD: /lib/x86_64-linux-gnu/libstdc++.so.6
                       │
                       └──► GLIBCXX_3.4.29 FOUND ✓ SUCCESS
                            (has correct symbols)

SUCCESS: simx_model.so loaded correctly
         All DPI functions available
```

## Two-Part Fix Explained

### Part 1: Static Linking (Defensive)
```c
// Makefile
LDFLAGS = -static-libstdc++ -static-libgcc

// Generates:
simx_model.so {
  // Contains embedded:
  - simx_*.cpp compiled objects (our code)
  - libstdc++.a (full C++ runtime embedded)
  - libgcc.a (GCC runtime embedded)
  
  // Does NOT require external libstdc++.so
}

Result: simx_model.so is self-contained
```

### Part 2: Runtime Preload (Corrective)
```bash
# run_vortex_uvm_enhanced.sh
export LD_PRELOAD=/lib/x86_64-linux-gnu/libstdc++.so.6

# When vsim loads libraries:
# 1. LD_PRELOAD path is searched FIRST
# 2. libramulator.so finds correct libstdc++.so.6
# 3. Symbol resolution succeeds for GLIBCXX_3.4.29
# 4. All libraries load correctly
```

## Symbol Resolution Breakdown

```
libramulator.so needs: GLIBCXX_3.4.29 symbols

Questa's libstdc++.so.6:  GLIBCXX_3.4.25 MAX ✗
                          ├─ __cxxabi_1.3
                          ├─ GLIBCXX_3.4
                          ├─ GLIBCXX_3.4.1
                          └─ GLIBCXX_3.4.25

System libstdc++.so.6:    GLIBCXX_3.4.29 ✓ (via LD_PRELOAD)
                          ├─ __cxxabi_1.3
                          ├─ GLIBCXX_3.4
                          ├─ GLIBCXX_3.4.1
                          ├─ GLIBCXX_3.4.25
                          └─ GLIBCXX_3.4.29 ← HERE!

LD_PRELOAD ensures system version is used
```

## Order of Execution

```
Timeline:
─────────────────────────────────────────────────────────

$ ./run_vortex_uvm_enhanced.sh --test=vortex_smoke_test
       │
       └─ Calls: scripts/run_vortex_uvm_enhanced.sh
              │
              ├─ Runs environment check
              │
              ├─ Builds SimX DPI:
              │  └─ g++-11 -static-libstdc++ ... ✓
              │
              ├─ Reaches vsim section:
              │  ├─ export LD_PRELOAD=...
              │  ├─ vsim -c vortex_tb_top ...
              │  │  └─ [LD_PRELOAD active during loading]
              │  │     ├─ loads simx_model.so ✓ (static, self-contained)
              │  │     ├─ loads libramulator.so (via LD_PRELOAD libstdc++) ✓
              │  │     └─ simulation runs ✓
              │  └─ unset LD_PRELOAD
              │
              └─ Simulation complete ✓
```

## System Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    Vortex UVM Verification                   │
├──────────────────────────────────────────────────────────────┤
│                                                                │
│  Test Execution:                                              │
│  ├─ UVM Testbench (SystemVerilog)                            │
│  │  └─ References: simx_init, simx_run, simx_read_mem, ...  │
│  │                                                             │
│  └─ DPI Layer (C++)                                           │
│     └─ simx_model.so (DPI Library)                           │
│        ├─ Linked Objects: SimX processor model               │
│        ├─ Static Runtime: libstdc++, libgcc (embedded)       │
│        └─ Dynamic Runtime: libramulator.so                   │
│           └─ Resolved via: LD_PRELOAD (/lib/x86_64.../...)  │
│                                                                │
├──────────────────────────────────────────────────────────────┤
│ GLIBCXX_3.4.29 Resolution Chain:                             │
│ ────────────────────────────────────────                     │
│                                                                │
│ vsim requests libstdc++ symbols                              │
│   │                                                            │
│   ├─ Checks: LD_PRELOAD paths    ← /lib/x86_64.../... ✓   │
│   │  (symbol GLIBCXX_3.4.29 found)                           │
│   │                                                            │
│   ├─ Would check: LD_LIBRARY_PATH (skipped if found above)   │
│   ├─ Would check: System directories (skipped if found)      │
│   └─ Would check: Questa bundled (NEVER REACHED)            │
│      (has max GLIBCXX_3.4.25 - too old)                      │
│                                                                │
└──────────────────────────────────────────────────────────────┘
```

## GCC Timeline

```
GCC Version History (relevant to GLIBCXX symbols):

GCC 4.x  ──────► GLIBCXX_3.4 - 3.4.7
GCC 5.x  ──────► GLIBCXX_3.4 - 3.4.22
GCC 7.4  ──────► GLIBCXX_3.4 - 3.4.25  ← Questa 2021.2 bundled
│
│ [SYMBOL GAP - GLIBCXX_3.4.29 NOT AVAILABLE]
│
GCC 10.x ──────► GLIBCXX_3.4 - 3.4.28
GCC 11.x ──────► GLIBCXX_3.4 - 3.4.29  ← System (Ubuntu 22.04)

Our Solution:
• Build with GCC 11 (gets GLIBCXX_3.4.29 symbols)
• Embed runtime static (simx_model.so self-contained)
• Preload system libstdc++ (provides GLIBCXX_3.4.29)
• Result: No dependency on Questa's old GCC
```

## Impact

```
Before Fix:
┌─────────────────────────────────────────────────┐
│ ✗ Cannot load SimX golden model (DPI failure)   │
│ ✗ Golden model verification not possible        │
│ ✗ Testing relies on RTL-only validation         │
│ ✗ Requires hours of debugging & experimentation│
└─────────────────────────────────────────────────┘

After Fix:
┌─────────────────────────────────────────────────┐
│ ✓ DPI library loads successfully                │
│ ✓ SimX golden model active in testbench        │
│ ✓ Comprehensive verification with both RTL+sim │
│ ✓ Tests run immediately (automatic workaround) │
├─────────────────────────────────────────────────┤
│ TIME SAVED: Hours of debugging → Minutes       │
│ QUALITY: Gold model + RTL cross-validation     │
│ SCALABILITY: Works for all team members        │
└─────────────────────────────────────────────────┘
```

---

**TL;DR**: We set LD_PRELOAD to force the correct libstdc++ library, which contains GLIBCXX_3.4.29 symbols that vsim needs to load simx_model.so. This bypasses Questa's ancient GCC 7.4.0 bundled libstdc++.
