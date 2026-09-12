# IEEE Design & Test (D&T) Submission Package

## Why D&T (the pitch, for yourself and the cover letter)
D&T is a magazine: reviewers score insight and value to practitioners,
not incremental novelty. This feature leads with the lessons
(silenced-checker story, coverage-goes-down, golden-model audit) and
cites the arXiv preprint for full technical depth — no text recycling.

## Article type
Feature article (peer-reviewed magazine department).

## Title
When the Golden Model Is Wrong Too: Industrial-Grade Verification for
an Open-Source GPGPU

## Authors
Same order as all prior records (see author table in
JSA_SUBMISSION_METADATA.md — identical list).
Corresponding: Samuel Moussa, samuelmoussa64@gmail.com.

## Length
~3,300 words all-in (D&T ceiling ~5,000) — deliberately tight;
4-page compiled manuscript, 1 figure, 2 tables, 15 references.

## Cover letter (draft)

Dear Editors,

We submit the feature article "When the Golden Model Is Wrong Too:
Industrial-Grade Verification for an Open-Source GPGPU" for
consideration in IEEE Design & Test.

Your readers build and verify the processors this article is about.
We report the construction of the sign-off half of open-GPU
verification---per-instruction lockstep against a golden model, a
technique for verifying racy multi-core programs, and the first
published SIMT functional-coverage model---and, more importantly, the
practitioner lessons it produced: assertions silenced during bring-up
hid a real reset defect for months; fixing that defect measurably
lowered branch coverage; a coverage definition was itself defective;
and a lockstep flow audits the golden model as rigorously as the RTL,
catching a reference bug that a USENIX Security fuzzing campaign had
publicly mislabeled as a hardware defect. Every claim in the article
carries banked evidence; a full technical treatment is available as
our companion preprint (cited in the article).

We believe this is a D&T story at heart: methodology with teeth,
told through its failure stories. The work is original, not under
consideration elsewhere, and all authors have approved the
submission.

Sincerely,
Samuel Moussa (corresponding author), on behalf of all authors

## Submission mechanics
1. IEEE Author Portal (ScholarOne) for D&T: create submission,
   article type "Regular Submission / Feature".
2. Upload dt_vortex_uvm_feature.pdf (and .tex if source requested).
3. Paste cover letter; enter authors (same order; corresponding =
   Samuel Moussa).
4. Suggested reviewers (optional): researchers in RISC-V
   verification, GPU verification, or open-source silicon quality.
5. Note the companion arXiv preprint in the submission note (allowed
   and encouraged by IEEE magazines).
