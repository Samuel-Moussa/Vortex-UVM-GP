#include <stdint.h>
#include <math.h>

/* Minimal stubs for rvfloat helpers expected by float_dpi.cpp.
   Signatures guessed from symbol names; adjust if compile/link errors show different signatures. */

/* 64-bit floating compare less-or-equal: returns int (0/1) */
int rv_fle_d(double a, double b) { return a <= b ? 1 : 0; }

/* Add common helpers if needed */
double rv_fsqrt_d(double x) { return sqrt(x); }
double rv_fdiv_d(double a, double b) { return a / b; }
double rv_fmadd_d(double a, double b, double c) { return a*b + c; }

/* If other symbols appear, add them here similarly. */
