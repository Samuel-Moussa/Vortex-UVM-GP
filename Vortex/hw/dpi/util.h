#ifndef UTIL_H
#define UTIL_H

#include <stdint.h>
#include <stdbool.h>
#include <math.h>

static inline int32_t clamp_int32(int32_t x, int32_t min, int32_t max) {
    return x < min ? min : (x > max ? max : x);
}

static inline float clamp_float(float x, float min, float max) {
    return x < min ? min : (x > max ? max : x);
}

#endif
