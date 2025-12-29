#ifndef RVFLOATS_H
#define RVFLOATS_H

#include <math.h>

typedef double rv_float64_t;

static inline rv_float64_t rv_fsqrt(rv_float64_t x) { return sqrt(x); }
static inline rv_float64_t rv_fdiv(rv_float64_t a, rv_float64_t b) { return a / b; }
static inline rv_float64_t rv_fmadd(rv_float64_t a, rv_float64_t b, rv_float64_t c) { return a * b + c; }

#endif
