# ISPC base-algorithm solution by cauldnz

![Algorithm](https://img.shields.io/badge/Algorithm-base-green)
![Faithfulness](https://img.shields.io/badge/Faithful-yes-green)
![Parallelism](https://img.shields.io/badge/Parallel-yes-green)
![Bit count](https://img.shields.io/badge/Bits-1-green)

A sieve of Eratosthenes following the base algorithm, written in [ISPC](https://ispc.github.io/), the Intel® Implicit SPMD Program Compiler. The entire program is ISPC: the entry point, the timing loop, thread management, the sieve and the output. The only external calls are to the C library (`clock_gettime`, `aligned_alloc`/`free`, pthreads, `getenv`).

This is the base-algorithm companion to [solution_1](../solution_1), which uses a mod-30 wheel.

## Implementation

**Storage.** One bit per odd number: bit `i` stands for `2i + 1`, and a set bit means composite.

**The base algorithm.** An outer loop finds the next prime by scanning for the next clear bit, then clears its odd multiples, stepping `2 × factor` through the numbers (`factor` through the bits). It stops at the square root of the sieve size. In the source, **every composite is cleared by its own single-bit OR**; no operation clears more than one composite. The clearing routines follow the approach of mike-barber's Rust ([PrimeRust/solution_1](../../PrimeRust/solution_1)) and GordonBGood's Chapel ([PrimeChapel/solution_1](../../PrimeChapel/solution_1)) solutions:

- **Dense factors (below 128).** The odd multiples of `p` repeat with a period of `p` 64-bit words. Each period holds exactly 64 multiples at fixed word and bit offsets. The routine is instantiated for every odd factor below 128 with the factor as a compile-time constant (a `switch` over the factor, calling an inlined routine), so those 64 offsets and single-bit masks become immediates. Clearing starts at the period containing `p²`. Smaller multiples in that period are composite as well, except `p` itself, which is restored afterwards. Every odd value has a case, not only primes: the program uses no knowledge of which numbers are prime beyond 2 being the only even one.
- **Sparse factors (128 and above).** The same idea over bytes: 8 multiples repeat every `p` bytes, each at a fixed bit position. Their byte offsets are computed once per factor; the 8 single-bit masks depend only on `p mod 16`, so they are compile-time constants selected by a `switch`.

**Faithfulness.** All of a sieve's state lives in the `Sieve` struct. ISPC has no classes; a struct with functions taking it as their first argument is the closest equivalent. A new instance is created, with its buffer allocated at run time and sized from the sieve size, on every pass. Nothing is precomputed or carried between passes, and there are no external dependencies.

**Parallelism.** Multi-threaded runs start one pthread per thread, each running independent sieves. Results are reported for all, half and a quarter of the hardware threads, because SMT siblings share an L1 cache and fewer threads can complete more passes.

**Portability.** The x86-64 build carries SSE4 and AVX2 code paths, chosen at startup by ISPC's dispatcher. The ARM64 build targets NEON. The base algorithm leaves essentially nothing for SIMD to do (one composite per operation), so there is no AVX-512 path: it measured about 18% slower, because wider gangs only add overhead to scalar code.

## Run instructions

### Docker

```
docker build -t primes-ispc-base .
docker run --rm primes-ispc-base
```

### Native (Ubuntu 24.04)

```
sudo apt-get install ispc gcc
sh build.sh
./primes
```

`PRIMES_TEST=1 ./primes` checks the prime count for every power of ten from 10 to 10⁸ and some edge cases, prints the results and exits non-zero on any mismatch.

## Output

Intel Xeon @ 2.80 GHz, 2 vCPUs (shared cloud instance), Ubuntu 24.04, ISPC 1.22.0, AVX2 code path:

```
cauldnz-ispc-base;29486;5.000111;1;algorithm=base,faithful=yes,bits=1
cauldnz-ispc-base;54961;5.000481;2;algorithm=base,faithful=yes,bits=1
```

Self-test:

```
size 1 -> 0 primes (expected 0) 1
size 2 -> 1 primes (expected 1) 1
size 3 -> 2 primes (expected 2) 1
size 10 -> 4 primes (expected 4) 1
size 100 -> 25 primes (expected 25) 1
size 1000 -> 168 primes (expected 168) 1
size 10000 -> 1229 primes (expected 1229) 1
size 100000 -> 9592 primes (expected 9592) 1
size 1000000 -> 78498 primes (expected 78498) 1
size 10000000 -> 664579 primes (expected 664579) 1
size 100000000 -> 5761455 primes (expected 5761455) 1
size 127 -> 31 primes (expected 31) 1
size 16383 -> 1900 primes (expected 1900) 1
```
