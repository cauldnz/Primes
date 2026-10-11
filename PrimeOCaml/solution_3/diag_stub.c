/* Diagnostic only (experiment ox-012): a cheap tick counter for primes.ml.
   x86-64: rdtsc (TSC cycles). aarch64: cntvct_el0, the generic timer (not CPU cycles; its
   rate is cntfrq_el0). Elsewhere: clock_gettime(CLOCK_MONOTONIC) in ns.
   diag_ticks_are_cycles says whether ticks are cycles; diag_tick_hz gives the counter rate,
   or 0 when it must be calibrated against the monotonic clock (the TSC). */
#include <stdint.h>
#include <time.h>
#include <caml/mlvalues.h>

#if defined(__x86_64__)
#include <x86intrin.h>
static inline int64_t ticks(void) { return (int64_t)__rdtsc(); }
static int64_t hz(void) { return 0; }
static int cycles(void) { return 1; }
#elif defined(__aarch64__)
static inline int64_t ticks(void) {
  uint64_t v;
  __asm__ __volatile__("isb\n\tmrs %0, cntvct_el0" : "=r"(v) : : "memory");
  return (int64_t)v;
}
static int64_t hz(void) {
  uint64_t f;
  __asm__ __volatile__("mrs %0, cntfrq_el0" : "=r"(f));
  return (int64_t)f;
}
static int cycles(void) { return 0; }
#else
static inline int64_t ticks(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}
static int64_t hz(void) { return 1000000000LL; }
static int cycles(void) { return 0; }
#endif

intnat diag_ticks(value unit) { (void)unit; return (intnat)ticks(); }
value diag_ticks_byte(value unit) { (void)unit; return Val_long((intnat)ticks()); }

intnat diag_mono_ns(value unit) {
  struct timespec ts;
  (void)unit;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (intnat)((int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec);
}
value diag_mono_ns_byte(value unit) { return Val_long(diag_mono_ns(unit)); }

value diag_tick_hz(value unit) { (void)unit; return Val_long((intnat)hz()); }
value diag_ticks_are_cycles(value unit) { (void)unit; return Val_bool(cycles()); }
