# JSA Submission Package (paste-ready)

## Highlights (Elsevier: 3–5 bullets, ≤85 characters each)
- Complete UVM 1.2 environment and closure methodology for an open RISC-V GPGPU
- Five SIMT lockstep alignment rules, semi-formalized as soundness properties
- Two-pass load feed verifies racy programs at instruction granularity
- First published SIMT functional-coverage layer for RTL GPU verification
- Gate-checked exclusion methodology; defects found on both sides of the compare

## Cover letter (draft)

Dear Editors,

We submit our manuscript "SIMT-Aware Lockstep Verification and
Functional-Coverage Closure Methodology for an Open-Source RISC-V
GPGPU: A Complete UVM 1.2 Environment" for consideration in the
Journal of Systems Architecture.

Open-source RISC-V GPGPUs ship today without reference-model
verification, functional-coverage models, or sign-off discipline,
while concurrent security work (FuzzGPU, USENIX Security 2026)
demonstrates real defects in exactly this design class. Our paper
addresses the complementary half of that problem: a complete,
evidence-disciplined verification methodology for the Vortex GPGPU.
Its contributions fit JSA's scope on embedded and special-purpose
system architecture, design methodology, and dependability:
a configuration-parametric UVM environment with role-inverted agents;
per-instruction, per-lane lockstep for SIMT via five alignment rules
semi-formalized as precondition-soundness properties; a two-pass
load-value feed that verifies racy multi-core programs at instruction
granularity with a characterized soundness boundary; the first
published SIMT functional-coverage layer for RTL GPU verification
(IPDOM divergence depth, scratchpad bank conflicts, coalescing
classes), closed under machine-generated, gate-checked exclusions;
and measured verification costs and per-generator marginal-coverage
evidence, including a head-to-head exercise of FuzzGPU's reported
findings at our pin — one reproduced as an RTL defect, one re-scoped
as a golden-model bug.

Every quantitative claim in the manuscript traces to a banked,
provenance-cited artifact; the boundaries of the method are stated
rather than waived, in a dedicated threats-to-validity section. All
authors have approved the submission. The work has not been published
elsewhere and is not under consideration by any other journal or
conference; an extended abstract version is available as a public
preprint (arXiv, cs.AR) for timestamping purposes only.

Suggested reviewers (optional, at your discretion): researchers
working on RISC-V verification methodology, GPU/GPGPU verification,
or open-source silicon quality.

Sincerely,
Samuel Moussa (corresponding author), on behalf of all authors

## Declarations
- **Competing interests**: none declared.
- **Funding**: this work was carried out as a graduation project at
  Minia University; no external funding.
- **Data availability**: all verification evidence (coverage bank
  reports, run logs, findings register, waiver generators) is
  available in the public artifact repository; machine-local raw
  UCDB binaries are described by their committed reports.
- **Author contributions (CRediT)**: S. Moussa: methodology,
  software, investigation, writing – original draft. S. Ibrahim,
  A. Sudky, A. Fawzy, A. Nabil: software, investigation,
  validation. A. Sayed, H. Hassan: supervision, methodology,
  writing – review & editing. H.-M. Yoon: supervision, writing –
  review & editing. (Adjust to actual contributions before
  submitting.)

## Submission mechanics checklist
1. Upload `jsa_vortex_uvm_manuscript.pdf` (or the .tex source;
   JSA's "Your Paper Your Way" accepts either for first submission).
2. Paste highlights (above) into the form.
3. Enter authors in order with affiliations; corresponding author:
   Samuel Moussa, samuelmoussa64@gmail.com.
4. Cover letter (above), adjusted as you see fit — note the parallel
   ISQED submission and the extension relationship explicitly.
5. Suggest opposite reviewers / exclude none, per your knowledge.

## Form abstract (199 words — fits the submission form's 200-word limit)
Open-source RISC-V GPGPUs ship without reference-model verification, functional-coverage models, or sign-off discipline, even as fuzzing shows real defects populate this class. This paper presents a complete UVM 1.2 environment and closure methodology for the Vortex RISC-V GPGPU. The environment wraps a bus-master SIMT device with role-inverted agents, integrates the project's functional simulator as a per-configuration golden model over DPI-C, and renders verdicts through two injection-qualified checkers: a bidirectional end-state scoreboard and a per-instruction, per-lane lockstep comparator governed by five alignment rules, semi-formalized as precondition-soundness properties. A two-pass load-value feed makes fenceless multi-core programs instruction-granularity verifiable - verified modulo the fed race resolutions, with the assumption discharged by a trace-level race witness in the flagship case. A three-layer coverage model adds, to our knowledge, the first published SIMT functional-coverage layer for RTL GPU verification (divergence depth, bank conflicts, coalescing classes), closed under machine-generated, RTL-cited exclusions enforced by a blocking waiver-integrity gate. The methodology surfaced externally corroborated RTL defects (a JALR LSB ISA deviation; a reset-relay X window behind a silenced assertion) and reference-model defects found by the lockstep itself. Lockstep adds no measurable wall-clock overhead and roughly 30% peak memory at scale; stimulus kind, not volume, moves this coverage model.
