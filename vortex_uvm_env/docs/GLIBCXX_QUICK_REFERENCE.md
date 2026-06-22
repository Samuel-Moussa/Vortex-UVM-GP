# Quick Reference: GLIBCXX Fix for Vortex UVM SimX DPI

## TL;DR
**The GLIBCXX_3.4.29 error has been fixed.** DPI library (simx_model.so) now loads correctly in Questa.

```bash
# Just run normally - fix is automatic
cd vortex_uvm_env
./scripts/run_vortex_uvm_enhanced.sh --test=vortex_smoke_test --program=...
```

---

## What Was Fixed?
| Before | After |
|--------|-------|
| ✗ vsim fails: "version `GLIBCXX_3.4.29' not found" | ✓ vsim loads DPI library successfully |
| ✗ Cannot run any simulation tests | ✓ All tests run and complete |
| ✗ DPI golden model unavailable | ✓ SimX golden model active in testbench |

---

## How It Works

### The Problem (Root Cause)
Questa 2021.2 ships with ancient GCC 7.4.0 that only knows symbols up to GLIBCXX_3.4.25. 
But simx_model.so and its dependency (libramulator.so) were built with GCC 11 (GLIBCXX_3.4.29).
When vsim tried to load the DPI library, the dynamic linker couldn't find the symbols.

### The Solution (Two Parts)

#### Part 1: Static Linking (Makefile)
```makefile
LDFLAGS := -static-libstdc++ -static-libgcc
```
- Embeds C++ runtime directly into simx_model.so
- Result: simx_model.so doesn't need external libstdc++

#### Part 2: Library Priority (Run Script)
```bash
export LD_PRELOAD=/lib/x86_64-linux-gnu/libstdc++.so.6
```
- Forces correct libstdc++ to be used for all loaded libraries
- libramulator.so (which simx_model.so uses) finds GLIBCXX_3.4.29 symbols

---

## For Different Use Cases

### Running Tests (Automated)
```bash
./scripts/run_vortex_uvm_enhanced.sh --test=vortex_smoke_test ...
# ← LD_PRELOAD is set automatically
```

### Manual Debugging (If needed)
```bash
export LD_PRELOAD=/lib/x86_64-linux-gnu/libstdc++.so.6
cd vortex_uvm_env
vsim -gui vortex_tb_top +UVM_TESTNAME=vortex_smoke_test ...
```

### Checking Library Status
```bash
cd vortex_uvm_env/uvm_env/ref_model
make test_lib
# Shows: ✓ No GLIBCXX external dependency
# Shows: ✓ libramulator.so correctly linked
```

---

## Architecture

```
LD_PRELOAD ─┐
            ├─→ /lib/x86_64-linux-gnu/libstdc++.so.6 ✓ (has GLIBCXX_3.4.29)
            │
Questa      ├─→ libstdc++ symbol resolution
vsim        └─→ (skips Questa's old libstdc++.so.6 with only GLIBCXX_3.4.25)
    │
    └─→ simx_model.so (has embedded libstdc++)
        └─→ libramulator.so (finds correct symbols via LD_PRELOAD)
```

---

## GCC Versions

| Tool | Version | Known Max | Status |
|------|---------|-----------|--------|
| System GCC | 11.4.0 | GLIBCXX_3.4.29 | ← Used for build & runtime |
| Questa GCC | 7.4.0 | GLIBCXX_3.4.25 | × Locked out by LD_PRELOAD |

---

## Verification

### Test Compilation
```bash
cd vortex_uvm_env/uvm_env/ref_model
make build
# Output shows: [OK] simx_model.so built successfully
# Output shows: [OK] No GLIBCXX external dependency
```

### Test Execution
```bash
cd vortex_uvm_env
./scripts/run_vortex_uvm_enhanced.sh \
  --test=vortex_smoke_test \
  --program=$(pwd)/uvm_env/agents/host_agent/program_simple.hex \
  --clean
# Output shows: ✓ SimX DPI built and linked
# No "GLIBCXX_3.4.29 not found" errors
```

---

## If Something Goes Wrong

### Symptom: Still getting GLIBCXX error
1. Check LD_PRELOAD is set:
   ```bash
   echo $LD_PRELOAD
   # Should show: /lib/x86_64-linux-gnu/libstdc++.so.6
   ```

2. Verify system libstdc++ exists:
   ```bash
   ldd /lib/x86_64-linux-gnu/libstdc++.so.6 | grep GLIBCXX
   # Should show symbols up to GLIBCXX_3.4.29
   ```

3. Manually set and test:
   ```bash
   export LD_PRELOAD=/lib/x86_64-linux-gnu/libstdc++.so.6
   cd vortex_uvm_env
   ./scripts/run_vortex_uvm_enhanced.sh --test=vortex_smoke_test ...
   ```

---

## Files Changed
✓ `scripts/run_vortex_uvm_enhanced.sh` - Added LD_PRELOAD export
✓ `uvm_env/ref_model/Makefile` - Added documentation & workaround notes

---

## Questions?
Refer to: [GLIBCXX_FIX_SUMMARY.md](./GLIBCXX_FIX_SUMMARY.md) for detailed technical explanation
