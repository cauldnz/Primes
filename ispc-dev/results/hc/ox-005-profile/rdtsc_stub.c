/* Diagnostic only: rdtsc for primes_diag.ml. Returns an untagged int, no allocation. */
#include <stdint.h>
#include <x86intrin.h>
#include <caml/mlvalues.h>
intnat diag_rdtsc(value unit) { (void)unit; return (intnat)__rdtsc(); }
value diag_rdtsc_byte(value unit) { (void)unit; return Val_long((intnat)__rdtsc()); }
