# Draft: academic access request to Imperas for riscvISACOV

**Not sent.** For Samuel to review, edit and send. Contact route: the invitation in
`third_party/riscvISACOV/source/coverage/README.md` ("please contact Imperas for full
access"); Imperas is now part of Synopsys, so the current address should be confirmed from
the repo's own issue tracker or the riscv-verification GitHub org before sending.

Two things to fix in the repo either way, worth raising in the same message because both
are genuine ambiguities for a downstream user, not complaints:

* every source file header carries `SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0`, but
  no file in the repository contains SHL-2.0 rider text, and `SHL-2.0` does not appear to
  be a registered SPDX identifier (the Solderpad identifiers are `SHL-0.51` and `SHL-2.1`).
* `ChangeLog.md` carries a proprietary header ("CONFIDENTIAL INFORMATION AND TRADE SECRETS
  … USE, DISCLOSURE, OR REPRODUCTION IS PROHIBITED") that contradicts `LICENSE.md`'s plain
  statement that the public repository is Apache-2.0.

---

**Subject:** riscvISACOV — academic access request, and two licence questions

Hello,

I am a final-year engineering student at Minia University. My graduation project is a UVM
verification environment for the Vortex open-source RISC-V GPGPU, with per-instruction
lockstep against a golden model and roughly 94% total code coverage across three
configurations.

I am adding riscvISACOV as an independent, third-party ISA functional-coverage model, so
that my own covergroups are cross-checked by something I did not write. It is integrated
and working: RV32I compiles and samples against real RTL retirements through an RVVI-TRACE
shim, using `idvPkg`/`idvApiPkg` stubs (the actual dependency turned out to be two
functions, so no ImperasDV licence was needed — you may want to note that in the README,
as the import list makes the dependency look much heavier than it is).

I have two requests and two questions.

**1. Academic access to the full coverage source.** `source/coverage/README.md` invites
contact for full access. My immediate interest is RV32M and RV32F — the design has hardware
divide and an FPU, and those are exactly the units where I most want an independent
opinion. If there is an academic or evaluation arrangement, I would be glad to hear the
terms. I am happy to cite riscvISACOV in the thesis and in any resulting publication.

**2. A generator I built, and whether you object to it.** While waiting, I wrote a tool
that generates extension coverage source from the DV-plan CSVs you publish in `dvplans/`,
using one template per coverage TYPE. I validated it by regenerating RV32I from its own
dvplan and diffing against your `RV32I_coverage.svh`: the output is byte-identical, 39
covergroups and 559 coverpoint rows, and the `_init.svh` matches as well. I have used it to
produce RV32M, which now runs against my design.

I want to be straightforward about this rather than quiet. The inputs — the dvplans, the
documentation and the RV32I sample — are all Apache-2.0 in your public repository, and my
generator and its output are my own work under Apache-2.0, with your repository left
unmodified. But the generated files stand where a commercial product otherwise would, so:

* **Do you object to the generator or its output being published** as part of my thesis
  and its open-source repository?
* **Would you rather I not publish it**, in exchange for access to the real thing?

I would rather ask first and follow your answer than publish and find out afterwards. If
you would like to see the generator before deciding, I will send it.

**3. Two licence points**, raised only because they affect anyone downstream:

* Source headers say `Apache-2.0 WITH SHL-2.0`, but no SHL-2.0 text is in the repository
  and `SHL-2.0` does not appear to be a registered SPDX identifier — should this be
  `SHL-2.1`, or is the rider intentional?
* `ChangeLog.md`'s proprietary header contradicts `LICENSE.md`'s Apache-2.0 statement.

Thank you for publishing the DV plans and the RV32I sample — the model is genuinely
well-built, and being able to read the specification for all 143 extensions is already
valuable.

Best regards,
Samuel Moussa
Minia University
[email / repository link]
