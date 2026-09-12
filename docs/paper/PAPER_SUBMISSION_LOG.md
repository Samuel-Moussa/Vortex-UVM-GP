# Paper Submission Log

Venue strategy and decision record for the publication program.
Maintained with the same discipline as the evidence registers.

## Timeline

| Date | Event | Notes |
|---|---|---|
| 2026-09-09/12 | Conference-strength paper (ISQED'27 format) + arXiv preprint + JSA skeleton prepared | Full adversarial review cycle executed; all majors addressed |
| 2026-09-12 | **Strategy decision: JSA-only; ISQED'27 not submitted** | Sept 17 deadline skipped in favor of journal route |
| 2026-09-12 | JSA manuscript completed (all sections, 36pp review-mode) | Machine-work package W0–W7 fully folded in |
| 2026-09-1x | **JSA submission** (Research Paper) | |
| 2026-1x | **JSA rejection: "out of scope" + "insufficient novelty"** | Editor triage, no peer review — scope mismatch (systems-architecture venue evaluating a verification-methodology paper), not a review verdict. Do not over-update on it. |
| 2026-1x | **arXiv preprint posted** | Work timestamped and citable; FuzzGPU-priority concern defused. arXiv ID: ______________ (fill in) |

## Artifacts on file (docs/paper/)

- `arxiv_vortex_uvm_2026.tex/.pdf` + `arxiv_vortex_uvm_source.tar.gz` — the posted preprint (12pp IEEE)
- `isqed27_vortex_uvm.tex/.pdf` — 8pp IEEE conference format, double-blind-clean, fully corrected; **the DVCon Europe 2027 base artifact**
- `jsa_vortex_uvm_manuscript.tex/.pdf` — 36pp extended journal manuscript; **the D&T / MICPO / journal-route base artifact**
- `PRESUBMISSION_DISCLOSURES.md` — honesty register governing every number (venue-independent)

## Next-venue plan (decided 2026-1x, post-rejection)

1. **DVCon Europe 2027** (primary; CFP ~Apr–Jun 2027) — methodology audience,
   usefulness-weighted review. Reuse: de-blind the 8pp paper + author block.
2. **IEEE Design & Test** (parallel option, rolling) — practitioner-insight lens;
   compress the 36pp manuscript to ~5k words.
3. Fallbacks: SAMOS XXVII (~Feb 2027 deadline), MICPRO, ESL letter.

Cover-letter novelty framing for all future submissions (learned from the
JSA triage): lead with the methodology-novelty story — first published SIMT
functional-coverage model with closure evidence; semi-formalized alignment
rules; gate-checked exclusion methodology; the symmetric findings exchange
with FuzzGPU (our R1 ↔ their S2; their X2 ↔ our golden-model thesis).
