// fpu_test — directed single-precision FP kernel to drive FPU coverage.
//
// Single-threaded (no vx_spawn → not affected by INV-1). Exercises a spread of
// RV32-F operations so that (a) the FPU EX unit dispatches, populating the
// instr_class_cg_fpu covergroup, (b) the FPU datapath is checked DUT-vs-SimX
// (SimX supports F via softfloat), and (c) FPU RTL control logic toggles.
//
// __builtin_* are used so specific instructions are emitted (not libcalls):
//   fadd.s fsub.s fmul.s fdiv.s fsqrt.s fmadd.s fmin.s fmax.s fsgnj(copysign)
//   fcvt.w.s/fcvt.s.w (int<->float) fcmp (feq/flt/fle) fclass.

#include <stdio.h>
#include <vx_print.h>

// volatile inputs so the compiler cannot constant-fold the FP ops away
volatile float A = 3.5f;
volatile float B = 1.25f;
volatile int      I = 7;
volatile unsigned U = 9;

// results stored to memory → scoreboard compares DUT vs SimX end-state
volatile float    R[13];
volatile int      IC[3];

int main() {
    float a = A, b = B;

    R[0]  = a + b;                       // fadd.s
    R[1]  = a - b;                       // fsub.s
    R[2]  = a * b;                       // fmul.s
    R[3]  = a / b;                       // fdiv.s
    R[4]  = __builtin_sqrtf(a);          // fsqrt.s
    R[5]  = __builtin_fmaf(a, b, a);     // fmadd.s
    // fnmadd.s (INST_FPU_NMADD): -(a*b)-a. Inline asm forces the real opcode —
    // clang lowers -__builtin_fmaf(a,b,a) to fmadd+fneg (fsgnjn = fmisc), so the
    // fnmadd bin would otherwise never execute on the taken path.
    { float r6; __asm__ volatile("fnmadd.s %0, %1, %2, %1" : "=f"(r6) : "f"(a), "f"(b)); R[6] = r6; }
    R[7]  = __builtin_fminf(a, b);       // fmin.s
    R[8]  = __builtin_fmaxf(a, b);       // fmax.s
    R[9]  = __builtin_copysignf(a, -b);  // fsgnj(n).s
    R[10] = (float)I;                    // fcvt.s.w  (i2f  / INST_FPU_I2F)
    R[11] = a * a - b;                   // fmsub.s / chained
    R[12] = (float)U;                    // fcvt.s.wu (u2f  / INST_FPU_U2F)

    IC[0] = (int)(a * b);                // fcvt.w.s  (f2i  / INST_FPU_F2I)
    IC[1] = (a > b) ? 1 : 0;             // fcmp (flt/fle)
    IC[2] = (int)(unsigned)(a * b);      // fcvt.wu.s (f2u  / INST_FPU_F2U)

    // Console output (also compared) + a simple self-check the result is sane.
    vx_printf("fpu_test: add=%d/100 mul=%d/100 sqrt~%d/100\n",
              (int)(R[0] * 100), (int)(R[2] * 100), (int)(R[4] * 100));

    int errors = 0;
    if (IC[0] != 4)            errors++;   // 3.5*1.25 = 4.375 -> trunc 4
    if (IC[1] != 1)            errors++;   // 3.5 > 1.25
    if (IC[2] != 4)            errors++;   // (unsigned)4.375 -> 4 (f2u)
    if (!(R[0] > 4.7f && R[0] < 4.8f)) errors++;  // 4.75
    if (!(R[12] > 8.9f && R[12] < 9.1f)) errors++;  // (float)9u = 9.0 (u2f)

    if (errors == 0) vx_printf("Passed!\n");
    else             vx_printf("Failed! errors=%d\n", errors);

    return errors;
}
