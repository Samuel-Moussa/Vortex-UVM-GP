#!/usr/bin/env bash
# =============================================================================
# merge_coverage.sh — merge a CONTROLLED SET of per-test UCDBs into one report.
# Implements plan COV-METH (Part 3.2-3.3).
#
# Contamination fix: the merge consumes ONLY ucdbs staged in cov/staging/,
# NOT every coverage.ucdb under results/. You choose what goes in, so old
# runs / wrong-config runs can't silently pollute the number.
#
#   cov/staging/<test>_<cfg>.ucdb  (you stage these — see --collect / collect_cov.sh)
#                  │  vcover merge
#                  ▼
#       cov/merged_raw.ucdb
#                  │  apply scripts/coverage_exclude.do
#                  ▼
#       cov/merged.ucdb  ──►  HTML + functional + code + summary
#
# Usage:
#   ./merge_coverage.sh                 # merge everything currently in cov/staging/
#   ./merge_coverage.sh --fresh         # CLEAR staging first, then exit (start clean)
#   ./merge_coverage.sh --collect R...  # copy named results/<R>/reports/coverage.ucdb
#                                       #   into staging, then merge
#   ./merge_coverage.sh --list          # show what's currently staged
#
# Typical flow for a clean 4-kernel report:
#   ./merge_coverage.sh --fresh
#   make sim TEST=kernel_launch_test PROGRAM_NAME=vecadd    TIMEOUT=10000000
#   make sim TEST=kernel_launch_test PROGRAM_NAME=conform   TIMEOUT=10000000
#   make sim TEST=kernel_launch_test PROGRAM_NAME=fibonacci TIMEOUT=10000000
#   make sim TEST=kernel_launch_test PROGRAM_NAME=hello     TIMEOUT=10000000
#   # each run auto-stages itself IF you add the collect hook to simulate.sh
#   # (see collect snippet); otherwise stage manually:
#   ./merge_coverage.sh --collect 20260620/run_AAA 20260620/run_BBB ...
#   ./merge_coverage.sh
# =============================================================================
set -uo pipefail

# This script lives in scripts/ ; ENV_ROOT is its PARENT (the env root),
# resolved symlink-safe exactly like run.sh does.
if [[ -L "${BASH_SOURCE[0]}" ]]; then _SP="$(readlink -f "${BASH_SOURCE[0]}")"; else _SP="${BASH_SOURCE[0]}"; fi
SCRIPTS_DIR="$(cd "$(dirname "$_SP")" && pwd)"
ENV_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
RESULTS_ROOT="${ENV_ROOT}/results"
# Config-aware exclusions: the .do is GENERATED per-config by gen_coverage_exclude.sh
# so each config's report only excludes what is structurally dead for THAT topology.
# Override the config via env, e.g.  COV_NCL=2 COV_NC=2 ./merge_coverage.sh
GEN_EXCLUDE="${SCRIPTS_DIR}/gen_coverage_exclude.sh"
COV_NCL="${COV_NCL:-1}"; COV_NC="${COV_NC:-1}"; COV_NW="${COV_NW:-4}"; COV_NT="${COV_NT:-4}"
COV_DIR="${ENV_ROOT}/cov"
STAGING="${COV_DIR}/staging"
OUT_DIR="${COV_DIR}/report"
RAW_UCDB="${COV_DIR}/merged_raw.ucdb"
MERGED_UCDB="${COV_DIR}/merged.ucdb"

export LD_PRELOAD="${LD_PRELOAD:-/usr/lib/x86_64-linux-gnu/libstdc++.so.6}"
mkdir -p "$STAGING" "$OUT_DIR"

# ---- subcommands ------------------------------------------------------------
case "${1:-}" in
  --fresh)
      rm -f "$STAGING"/*.ucdb 2>/dev/null || true
      rm -f "$RAW_UCDB" "$MERGED_UCDB" 2>/dev/null || true
      echo "Staging cleared: $STAGING"
      echo "Now run your tests, stage them (--collect), then merge."
      exit 0 ;;
  --list)
      echo "Staged UCDBs in $STAGING:"
      ls -1 "$STAGING"/*.ucdb 2>/dev/null | sed 's/^/  /' || echo "  (none)"
      exit 0 ;;
  --collect)
      shift
      [[ $# -eq 0 ]] && { echo "ERROR: --collect needs run dir(s), e.g. 20260620/run_xxx"; exit 1; }
      for r in "$@"; do
          src="${RESULTS_ROOT}/${r}/reports/coverage.ucdb"
          if [[ -f "$src" ]]; then
              # unique staged name from the run dir, so re-collecting overwrites
              # the same test rather than double-counting it.
              name="$(echo "$r" | tr '/' '_').ucdb"
              cp "$src" "${STAGING}/${name}"
              echo "Staged: $r  ->  ${name}"
          else
              echo "WARN: no ucdb at $src"
          fi
      done
      echo "Proceeding to merge staged set..."
      ;;
  "" ) : ;;  # no arg → merge whatever is staged
  * )  echo "Unknown option: $1"; echo "Use --fresh | --collect <runs> | --list | (no arg)"; exit 1 ;;
esac

# ---- 1. collect staged ucdbs ------------------------------------------------
declare -a UCDBS=()        # <-- declare empty FIRST so set -u never trips
while IFS= read -r f; do UCDBS+=("$f"); done \
    < <(find "$STAGING" -maxdepth 1 -name '*.ucdb' 2>/dev/null | sort)

if [[ ${#UCDBS[@]} -eq 0 ]]; then
    echo "ERROR: nothing staged in $STAGING"
    echo "  Stage runs first:  ./merge_coverage.sh --collect <runDir> [<runDir>...]"
    echo "  (runDir is the path under results/, e.g. 20260620/run_153012_kernel_launch_test)"
    exit 1
fi

echo "Merging ${#UCDBS[@]} staged UCDB(s):"
printf '  %s\n' "${UCDBS[@]##*/}"

# ---- 2. merge ---------------------------------------------------------------
vcover merge -out "$RAW_UCDB" "${UCDBS[@]}"
[[ $? -eq 0 && -f "$RAW_UCDB" ]] || { echo "ERROR: vcover merge failed"; exit 1; }

# ---- 3. apply CONFIG-AWARE exclusions once, re-save -------------------------
if [[ -x "$GEN_EXCLUDE" ]]; then
    EXCLUDE_DO="${COV_DIR}/coverage_exclude.gen.do"
    echo "Generating config-aware exclusions for ${COV_NCL}CL/${COV_NC}C/${COV_NW}W/${COV_NT}T -> $EXCLUDE_DO"
    "$GEN_EXCLUDE" "$COV_NCL" "$COV_NC" "$COV_NW" "$COV_NT" > "$EXCLUDE_DO"
    vsim -viewcov "$RAW_UCDB" -c -do "
        do ${EXCLUDE_DO};
        coverage save ${MERGED_UCDB};
        quit -f;" 2>&1 | tee "${COV_DIR}/exclude_apply.log" | grep -Ei "had no effect|error|excluded" || true
    # NOTE: `grep -c` prints "0" AND exits 1 when there are no matches, so the old
    # `|| echo 0` fired IN ADDITION to grep's own output and set HNE to the two-line
    # string "0\n0". `[[ "0\n0" -eq 0 ]]` is then a syntax error, which took the
    # `||` branch and printed a bogus "WARN: 0\n0 exclusion line(s) had no effect".
    # So this guard — the one that proves the config-aware exclusions actually
    # matched real RTL paths — could never report a TRUE count either: any genuine
    # stale-exclusion count would have been reported as garbage too. Use `|| HNE=0`
    # on the ASSIGNMENT so grep's numeric output is kept and only the exit status is
    # swallowed.
    HNE=$(grep -c "had no effect" "${COV_DIR}/exclude_apply.log" 2>/dev/null) || HNE=0
    [[ "${HNE:-0}" -eq 0 ]] || echo "WARN: $HNE exclusion line(s) had no effect (stale path for this config?)"
    [[ -f "$MERGED_UCDB" ]] || { echo "ERROR: exclusion/save failed"; exit 1; }
else
    echo "WARN: $GEN_EXCLUDE missing/not-exec — merging WITHOUT exclusions (cvfpu in denominator!)"
    cp "$RAW_UCDB" "$MERGED_UCDB"
fi

# ---- 4. reports -------------------------------------------------------------
vcover report -html -output "${OUT_DIR}/html" -details -threshL 90 -threshH 100 "$MERGED_UCDB" >/dev/null 2>&1
vcover report -cvg -details       "$MERGED_UCDB" > "${OUT_DIR}/functional.txt" 2>/dev/null
vcover report -details -code bcst "$MERGED_UCDB" > "${OUT_DIR}/code.txt"       2>/dev/null
vcover report -summary            "$MERGED_UCDB" > "${OUT_DIR}/summary.txt"    2>/dev/null

echo ""
echo "=============================================================="
echo " MERGED COVERAGE (Vortex-RTL scope, cvfpu/third-party waived)"
echo " Sources: ${#UCDBS[@]} staged UCDB(s)"
echo "=============================================================="
cat "${OUT_DIR}/summary.txt" 2>/dev/null
echo "--------------------------------------------------------------"
echo " HTML        : ${OUT_DIR}/html/index.html"
echo " Functional  : ${OUT_DIR}/functional.txt"
echo " Code        : ${OUT_DIR}/code.txt"
echo " Merged UCDB : ${MERGED_UCDB}"
echo " Staged set  : ${STAGING}  (kept; clear with --fresh)"
echo "=============================================================="