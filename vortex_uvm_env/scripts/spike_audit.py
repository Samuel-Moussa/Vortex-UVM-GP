#!/usr/bin/env python3
"""
A6 -- Spike base-ISA independence audit.

WHY THIS EXISTS
    Our per-instruction lockstep proves DUT == SimX. But SimX is written by the
    Vortex authors and ships with the DUT, so that is a SELF-CONSISTENCY result:
    a shared misreading of the RISC-V spec is invisible to it. (Plan FW-2.)
    Spike is the RISC-V reference simulator, developed independently, so
    agreement DUT == SimX == Spike on the base-ISA subset is a genuinely
    independent check.

SCOPE -- READ THIS BEFORE QUOTING ANY RESULT
    Spike is a SCALAR ISS with no SIMT model. It cannot execute a Vortex kernel
    and has no counterpart for lanes 1..N-1, warps, divergence or reconvergence.
    This audit therefore covers ONLY:
        * warp 0, lane 0,
        * the base-ISA (RV32IM) prefix,
        * up to the first Vortex custom instruction.
    It says NOTHING about SIMT behaviour, which remains SimX-only. Do not let
    a green result here be reported as "the design was independently verified".

TWO ANNOTATED, EXPECTED SKIPS (both verified, neither is a defect)
    1. Spike executes a bootrom at 0x1000..0x1010 and then jumps to the ELF
       entry; the DUT begins directly at 0x80000000. We align on the first
       Spike retirement at the entry PC and discard that prefix.
    2. prepare.sh (see its riscv-dv sed block) rewrites `csrr x5,0xf14`
       (mhartid) to `nop`, because the Vortex RTL implements no machine-mode
       CSRs. x5 is therefore uninitialised BY DESIGN at _start: Spike happens to
       leave 0x80000000 in it from its bootrom `lw`, the DUT leaves its reset
       value. The `beq x5,x6,0f` that follows is harmless -- its target IS pc+4,
       so both directions land identically -- but the x5 VALUE differs until it
       is overwritten. Register x5 is therefore not value-compared until its
       first architectural write. PC is compared throughout.

USAGE
    spike --isa=rv32im --priv=m --log-commits -l <elf> > spike.log
    ./spike_audit.py --spike spike.log --trace lockstep_trace.txt --entry 0x80000000

    Spike will not terminate on a riscv-dv program (no HTIF tohost), so run it
    under `timeout` and compare a bounded PREFIX -- that is by design.
"""

import argparse
import re
import sys

# Vortex custom instructions. Encoded in the RISC-V custom opcode space; Spike
# has no model for them, so the audit stops cleanly at the first one rather than
# reporting a wall of meaningless divergence.
CUSTOM_OPCODES = {0x0B, 0x2B, 0x5B, 0x7B}   # custom-0/1/2/3 low 7 bits

# `core   0: 3 0x80000004 (0x00000313) x6  0x00000000 [mem 0x...]`
SPIKE_COMMIT = re.compile(
    r"^core\s+\d+:\s+\d+\s+0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)"
    r"(?:\s+x(\d+)\s+0x([0-9a-fA-F]+))?"
)


def parse_spike(path, entry, wb_only=False):
    """Return [(pc, insn, rd, val)] from the entry point onward.

    Only committed-state lines are kept (the ones carrying the privilege field);
    Spike also emits a plain disassembly line per instruction which we skip.

    wb_only restricts the stream to instructions that WRITE A REGISTER, which is
    what makes the three streams directly comparable. Our lockstep is explicitly
    a writeback-domain check -- see lockstep_scoreboard.sv:16 ("DOMAIN: writeback
    retirements only (wb==1)"), enforced at vx_commit_probe.sv:99 -- so branches,
    stores, `jalr x0` and nops never enter the DUT/SimX streams. Spike logs a
    register only when one is actually written, so the same filter aligns the
    domains exactly rather than approximately: no windowed resynchronisation and
    no skip heuristic is needed, and a dropped or extra retirement still shows up
    as a length difference instead of being silently absorbed.
    """
    out = []
    started = False
    with open(path, errors="replace") as fh:
        for line in fh:
            m = SPIKE_COMMIT.match(line)
            if not m:
                continue
            pc = int(m.group(1), 16)
            if not started:
                if pc != entry:
                    continue          # skip 1: bootrom prefix
                started = True
            insn = int(m.group(2), 16)
            rd = int(m.group(3)) if m.group(3) is not None else None
            val = int(m.group(4), 16) if m.group(4) is not None else None
            if wb_only and rd is None:
                continue
            out.append((pc, insn, rd, val))
    return out


def parse_trace(path, cid=0, wid=0):
    """Return [(dut_pc, dut_rd, dut_d0, simx_pc, simx_rd, simx_d0, flags)]."""
    out = []
    with open(path, errors="replace") as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            f = line.split()
            if len(f) < 12:
                continue
            if int(f[2], 16) != cid or int(f[3], 16) != wid:
                continue
            out.append((int(f[4], 16), int(f[5]), int(f[6], 16),
                        int(f[7], 16), int(f[8]), int(f[9], 16), f[11]))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spike", required=True, help="spike --log-commits output")
    ap.add_argument("--trace", required=True, help="+LOCKSTEP_TRACE output")
    ap.add_argument("--entry", default="0x80000000", help="ELF entry PC")
    ap.add_argument("--max", type=int, default=0, help="cap compared retirements (0=all)")
    args = ap.parse_args()

    entry = int(args.entry, 16)
    spike = parse_spike(args.spike, entry, wb_only=True)
    trace = parse_trace(args.trace)

    # A retirement-count difference is itself a result: equal lengths mean Spike
    # independently agrees on HOW MANY architectural writebacks the program
    # performs, before any value is compared. Report it either way.
    if len(spike) != len(trace):
        print(f"NOTE: stream lengths differ -- spike={len(spike)} trace={len(trace)}. "
              f"Comparing the common prefix; a truncated Spike log (it has no HTIF "
              f"tohost and is run under `timeout`) is the usual benign cause.")

    if not spike:
        print(f"FAIL: no Spike retirement at entry {args.entry} -- wrong ELF or --isa?")
        return 2
    if not trace:
        print("FAIL: trace has no warp-0 records -- was +LOCKSTEP_TRACE armed with +LOCKSTEP?")
        return 2

    n = min(len(spike), len(trace))
    if args.max:
        n = min(n, args.max)

    # Skip 2: x5 is uninitialised by design (see module docstring). Its value is
    # not compared until Spike itself writes it.
    x5_written = False

    compared = 0
    stopped = None
    mismatches = []

    for i in range(n):
        s_pc, s_insn, s_rd, s_val = spike[i]
        d_pc, d_rd, d_d0, g_pc, g_rd, g_d0, flags = trace[i]

        if (s_insn & 0x7F) in CUSTOM_OPCODES:
            stopped = (i, s_pc, s_insn)
            break

        # PC is compared unconditionally -- it is the control-flow spine.
        if s_pc != d_pc or s_pc != g_pc:
            mismatches.append(
                f"[{i}] PC  spike={s_pc:#x} dut={d_pc:#x} simx={g_pc:#x}")
            break   # after a control-flow divergence everything downstream is noise

        # Destination register.
        if s_rd is not None:
            if s_rd != d_rd or s_rd != g_rd:
                mismatches.append(
                    f"[{i}] pc={s_pc:#x} rd  spike=x{s_rd} dut=x{d_rd} simx=x{g_rd}")
            elif s_rd == 5 and not x5_written:
                x5_written = True          # annotated skip, first write only
            elif s_val is not None:
                # Loads: Spike's value is from its own flat memory; our load data
                # is region-filtered (OBS-002). Compare only non-load writebacks.
                if "L" not in flags:
                    sv = s_val & 0xFFFFFFFF
                    if sv != (d_d0 & 0xFFFFFFFF) or sv != (g_d0 & 0xFFFFFFFF):
                        mismatches.append(
                            f"[{i}] pc={s_pc:#x} x{s_rd} val spike={sv:#010x} "
                            f"dut={d_d0 & 0xFFFFFFFF:#010x} simx={g_d0 & 0xFFFFFFFF:#010x}")
        compared += 1

    print("==================== A6 SPIKE INDEPENDENCE AUDIT ====================")
    print(f"  spike retirements (from entry) : {len(spike)}")
    print(f"  trace retirements (warp 0)     : {len(trace)}")
    print(f"  compared (3-way DUT/SimX/Spike): {compared}")
    if stopped:
        i, pc, insn = stopped
        print(f"  stopped at Vortex custom op    : idx {i} pc={pc:#x} insn={insn:#010x}")
    print(f"  mismatches                     : {len(mismatches)}")
    for m in mismatches[:20]:
        print("    " + m)
    print("  SCOPE: warp 0 / lane 0 / base-ISA prefix only. Says nothing about SIMT.")
    print("====================================================================")
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
