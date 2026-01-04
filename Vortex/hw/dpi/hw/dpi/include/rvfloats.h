#ifndef RVFLOATS_H
#define RVFLOATS_H
#include <math.h>
/* Minimal rvfloats stub for simulation build.
   Expand if compilation errors request additional symbols. */

typedef double rv_float64_t;
static inline double rv_fsqrt(double x)   { return sqrt(x); }
static inline double rv_fdiv(double a,double b) { return a / b; }
static inline double rv_fmadd(double a,double b,double c) { return a*b + c; }

/* If float_dpi.cpp expects other helpers, add them here when errors appear. */
#endif
