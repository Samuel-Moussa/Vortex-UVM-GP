# Documentation

Project documentation for the Vortex UVM verification environment. See the
[top-level README](../README.md) for the overview, architecture, and results.

## Results

| Document | Purpose |
|----------|---------|
| [coverage/Coverage_Report_2026-07-10.md](coverage/Coverage_Report_2026-07-10.md) | Full coverage report — both configurations (1CL and 2CL) |
| [coverage/Coverage_Model_Reference.md](coverage/Coverage_Model_Reference.md) | Every covergroup, its coverpoints, and why it is sufficient |
| [appendices/AXI_SVA_report.md](appendices/AXI_SVA_report.md) | AXI4 assertion (SVA) report |

## Reference

| Document | Purpose |
|----------|---------|
| [VERIFICATION_PLAN_v2.md](VERIFICATION_PLAN_v2.md) | Verification strategy, testcases, and coverage goals — **current** |
| [verification_plan/VERIFICATION_PLAN.md](verification_plan/VERIFICATION_PLAN.md) | Earlier verification plan lineage — superseded by v2, kept for history |
| [INTERFACE_MAPPING.md](INTERFACE_MAPPING.md) | RTL interface → UVM agent signal-level mapping |
| [RISCV_DV_GUIDE.md](RISCV_DV_GUIDE.md) | Constrained-random (riscv-dv) pipeline |

## Engineering record

| Document | Purpose |
|----------|---------|
| [fixes/](fixes/) | Per-issue root-cause writeups (fix log + investigations) |
| [investigations/SimX_2CL_no_fence_divergence.md](investigations/SimX_2CL_no_fence_divergence.md) | Multi-cluster SimX divergence — root-caused as a golden-model limit, not a DUT bug |
