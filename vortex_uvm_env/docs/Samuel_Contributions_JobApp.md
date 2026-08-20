# Graduation Project — Job Application Answers (Samuel Moussa)

## Graduation project description

Vortex UVM — Functional Verification of an Open-Source RISC-V GPGPU. A
SystemVerilog/UVM verification environment for the Vortex RISC-V GPGPU
(multi-cluster/core/warp/thread, AXI memory interface) built in QuestaSim. It uses
the SimX instruction-set simulator as a golden reference via DPI-C for black-box,
end-state DUT-vs-reference equivalence checking, and integrates riscv-dv
constrained-random test generation alongside directed kernel tests, a scoreboard,
and functional/code coverage closure. My team of three verified the design
end-to-end across configurable topologies, achieving ~73% total coverage with a
trusted, self-checking regression flow.

## Contribution in graduation project

- Environment bring-up & infrastructure lead: integrated the full Vortex RTL with
  the UVM environment, fixed RTL/Questa compilation and DPI-C linking issues, and
  drove the first end-to-end smoke test to success.
- Testbench correctness (Gate-0): replaced fabricated/heuristic bench signals with
  real hardware taps — derived tag/ID widths from RTL, wired the true
  retired-instruction count and IPC, decoded real EBREAK for completion, and made
  the error gate honest (validated by a negative fault-injection test).
- Full configurability: made all probes and elaboration asserts parametric for any
  N clusters/cores/warps/threads, and fixed the SimX golden model to rebuild
  per-config for multi-core runs.
- Constrained-random (riscv-dv) pipeline: stood up riscv-dv generation end-to-end
  and got randomized arithmetic/stress tests passing and self-checking against the
  reference model.
- Co-simulation & coverage: restored DUT-vs-SimX co-simulation across all test
  types, authored directed kernels (FPU, barrier, divergence, warp-spawn,
  AXI-stress), and drove functional coverage from ~12% to ~73% with evidence-based,
  config-aware bin closure.
- Debug & root-cause: diagnosed a suspected multi-warp hang as printf I/O volume
  (not a hardware bug), unblocking multiple coverage and negative-test milestones.
