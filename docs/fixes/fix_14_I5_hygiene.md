---
issue: I5
commit: a42f164c
date: 2026-06-26
author: Samuel Moussa
---

# I5 — Hygiene: Remove Dead Files + Fix Stale `// 8` Comments

## Problem

Two classes of cruft were in the tree:

1. **Dead source files** — draft/backup copies that were never in any flist, never compiled, but still tracked or sitting in the working tree. They confuse anyone grepping the codebase (e.g. a search for `VX_MEM_TAG_WIDTH` returns hits in a dead `vortex_config2.sv` that is not the file actually compiled).

2. **Stale comments** — after C1 (commit 4c36bd82) replaced the hardcoded tag width `8`/`50` with `VX_gpu_pkg::VX_MEM_TAG_WIDTH`, several `// 8` trailing comments survived the edit. They now actively lie: the value is not 8 (it is 50 in a debug build, 7 in NDEBUG).

---

## Files Removed

| File | Tracked? | Method | Lines |
|------|----------|--------|-------|
| `vortex_uvm_env/uvm_env/vortex_config2.sv` | yes | `git rm` | 1137 |
| `vortex_uvm_env/tb/vortex_status_if_fixed.sv` | yes | `git rm` | 134 |
| `vortex_uvm_env/tb/vortec_tb_top_backup.sv` | no (untracked) | `rm` | 956 |
| `vortex_uvm_env/uvm_tests/vortex_smoke_test_backup.sv` | no (untracked) | `rm` | 523 |

**Verification before deletion:** grepped all flists, scripts, and the Makefile for references to each file — zero hits from live build inputs. The only references were in `docs/Vortex_UVM_Plan_Current.md` (which itself lists them as "to be removed").

```bash
grep -rn "vortex_config2\|vortex_status_if_fixed\|vortec_tb_top_backup\|smoke_test_backup" \
    vortex_uvm_env/flists/ vortex_uvm_env/scripts/ vortex_uvm_env/Makefile
# (no output — safe to delete)
```

Note on the two "fixed"/"2" names: these were earlier-iteration drafts. The live files are `vortex_config.sv` (uvm_env/) and `vortex_status_if` is folded into `vortex_if.sv`. Deleting the drafts removes the ambiguity.

---

## Stale Comments Fixed

### `vortex_uvm_env/uvm_env/vortex_config.sv`

Three sites, all changed from a literal `8` to the derived-value description:

| Line | Before | After |
|------|--------|-------|
| ~215 | `//   AXI_ID_WIDTH   = VX_MEM_TAG_WIDTH  = 8  (NOT 50, NOT 4)` | `= VX_gpu_pkg::VX_MEM_TAG_WIDTH (e.g. 50 debug, 7 NDEBUG)` |
| ~221 | `int unsigned AXI_ID_WIDTH;    // FIXED = 8 (= VX_MEM_TAG_WIDTH)` | `// = VX_gpu_pkg::VX_MEM_TAG_WIDTH (derived, not hardcoded)` |
| ~681 | `AXI_ID_WIDTH = VX_MEM_TAG_WIDTH;      // 8  — L3_MEM_TAG_WIDTH` | `// derived (e.g. 50 debug / 7 NDEBUG)` |
| ~913 | `mem_tag_width = VX_MEM_TAG_WIDTH;      // 8` | `// derived — see VX_gpu_pkg::VX_MEM_TAG_WIDTH` |
| ~916 | `AXI_ID_WIDTH = VX_MEM_TAG_WIDTH;    // 8` | `// derived (e.g. 50 debug / 7 NDEBUG)` |

(The `mem_tag_width // 8` pattern appeared twice — both replaced via `replace_all`.)

### `vortex_uvm_env/tb/vortex_if.sv`

| Line | Before | After |
|------|--------|-------|
| 16 | `//   AXI_ID_W   = vortex_config_pkg::AXI_ID_WIDTH    (8,   fixed = VX_MEM_TAG_WIDTH)` | `(derived = VX_gpu_pkg::VX_MEM_TAG_WIDTH)` |
| 47 | `//   AXI_ID_WIDTH   = 8   (VX_MEM_TAG_WIDTH = L3_MEM_TAG_WIDTH)` | `= VX_gpu_pkg::VX_MEM_TAG_WIDTH (derived, e.g. 50 debug / 7 NDEBUG)` |

**Important:** these were comment-only edits. No parameter value changed — the actual code already used `VX_MEM_TAG_WIDTH` (the C1 fix). Only the misleading `// 8` annotations were corrected. No recompile/behavior impact.

---

## Acceptance Check

- `git ls-files` no longer lists `vortex_config2.sv` or `vortex_status_if_fixed.sv`
- working tree no longer contains the two backup `.sv` files
- `grep -rn "= 8" vortex_config.sv vortex_if.sv` returns no tag-width comments claiming 8
- No build input referenced any removed file (verified pre-deletion) → no compile change needed to confirm; the next `make sim` for any other task will still pass

---

## Teammate Conflicts / Handover

**No conflicts.** Every removed file and every edited comment is in Samuel's infrastructure lane.

**Ahmad / Steven — awareness only:**
If either had a local uncommitted copy of `vortex_config2.sv` or `vortex_status_if_fixed.sv` they were referencing, those are now gone from the tree. Neither was ever in a flist, so no build relied on them. If a future grep surprises them, the canonical files are:
- config object → `vortex_uvm_env/uvm_env/vortex_config.sv`
- status interface → folded into `vortex_uvm_env/tb/vortex_if.sv`

---

## Remaining I5-Adjacent Cleanup (not done — low priority)

These were left in place deliberately (not dead, just noisy) and can be revisited if time permits:
- `modelsim.ini.backup`, `vortex_uvm_env/tb/backups/`, `vortex_uvm_env/scripts/backup/`, `vortex_uvm_env/flists/backup/` — backup *directories*, harmless, not in any build path. Left for a dedicated housekeeping pass.
- `.Zone.Identifier` files (Windows download markers) scattered across `third_party/` — cosmetic; not Samuel-authored; out of lane.
