# arXiv submission metadata (paste-ready)

## Title
SIMT-Aware Lockstep Verification and Functional-Coverage Closure Methodology for an Open-Source RISC-V GPGPU: A UVM 1.2 Environment

## Authors (in order)
Samuel Moussa; Steven Ibrahim; Ahmad Sudky; Ahmad Fawzy; Abanoub Nabil; Alhassan Sayed; Hossam Hassan; Hyung-Min Yoon

## Categories
Primary: cs.AR

## Comments field (suggested)
Extended version of a conference submission; 12 pages, IEEE format. Source package: arxiv_vortex_uvm_source.tar.gz

## Abstract (1,919 chars incl. spaces — verified under the 1,920 limit)
Open-source RISC-V GPGPUs such as Vortex ship with directed-kernel regressions but no reference-model checking, functional-coverage model, or sign-off discipline. This paper presents a UVM 1.2 environment and methodology that closes that gap. The environment wraps a bus-master SIMT DUT with role-inverted agents, integrates Vortex's functional simulator (SimX) as a per-configuration golden model over DPI-C, and renders verdicts via two injection-qualified checkers: a bidirectional end-state scoreboard and a per-instruction, per-lane lockstep comparator under five SIMT alignment rules. A two-pass load-value feed makes racy fenceless multi-core programs instruction-granularity verifiable (residual zero over 5,432 retirements), with the interrupt-timing boundary stated. A three-layer coverage model adds, to our knowledge, the first published SIMT functional-coverage layer for RTL GPU verification (divergence depth, bank conflicts, coalescing classes), closing its own layers at 98.1% covergroup-bin / 94.7% total (ISA layer separately: 83.1% bins / 89.3% weighted) under machine-generated, RTL-cited exclusions and a blocking waiver-integrity gate; an unstimulated D-extension elaboration affects no functional bin, only lowering totals. The checking depth surfaced real defects on both sides of the comparison: a JALR LSB ISA deviation, a non-scaling watchdog constant (since fixed upstream), a reset-relay X window found by restoring a silenced assertion, a missing AXI error path proven by fault injection, and a reference-model fetch bug found by the lockstep itself. FuzzGPU (USENIX Security 2026), a concurrent RTL GPU fuzzer on the same DUT, is complementary: fuzzing finds bugs, this methodology quantifies sign-off; both independently found the JALR deviation. All findings ship in an evidence-cited register; every number carries provenance and the method's boundaries are stated rather than waived.
(character count verified 2026-09-10; paste as-is into the arXiv abstract field)
