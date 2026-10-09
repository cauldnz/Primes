# ISPC solution by cauldnz

![Algorithm](https://img.shields.io/badge/Algorithm-base-green)
![Faithfulness](https://img.shields.io/badge/Faithful-yes-green)
![Parallelism](https://img.shields.io/badge/Parallel-yes-green)
![Bit count](https://img.shields.io/badge/Bits-1-green)

A sieve of Eratosthenes that follows the base algorithm, written in [ISPC](https://ispc.github.io/), Intel's Implicit SPMD Program Compiler. The whole program is ISPC: the entry point, the timing loop, the threads, the sieve and the output. It calls the C library only for the clock, memory allocation, pthreads and `getenv`.

[solution_1](../solution_1) is the wheel companion to this entry.

## Why ISPC, for the base algorithm

This entry is the counterpoint to solution_1. The base algorithm clears one composite per operation, which leaves the vector lanes almost nothing to share. ISPC compiles it to much the same scalar code that C, Rust or Chapel would produce, from the same LLVM backend. The wide targets hurt. On an Intel Xeon the AVX-512 build ran 18% slower than AVX2, because the extra lanes add overhead without adding work, so the build leaves AVX-512 out. Read together, the two entries show how much of ISPC's advantage depends on the algorithm leaving room for SIMD.

## Implementation

### Storage

One bit per odd number: bit `i` stands for `2i + 1`, and a set bit means composite.

### The base algorithm

An outer loop finds the next prime by scanning for the next clear bit, then clears that prime's odd multiples, stepping `2 × factor` through the numbers (`factor` through the bits). It stops at the square root of the sieve size. In the source, every composite is cleared by its own single-bit OR; no operation clears two composites. The clearing routines follow mike-barber's Rust solution ([PrimeRust/solution_1](../../PrimeRust/solution_1)) and GordonBGood's Chapel solution ([PrimeChapel/solution_1](../../PrimeChapel/solution_1)).

- **Factors below 128.** The odd multiples of `p` repeat with a period of `p` 64-bit words, and each period holds exactly 64 multiples at fixed word and bit offsets. A `switch` over the factor calls an inlined routine with the factor as a compile-time constant, so the compiler turns those 64 offsets and single-bit masks into immediates. Clearing starts at the period that contains `p²`. The smaller multiples in that period are composite too; only `p` itself is restored afterwards. Every odd factor has a case, including 9, 15 and the other composites, so the program assumes nothing about which numbers are prime beyond 2 being the only even one.
- **Factors of 128 and above.** The same idea over bytes: eight multiples repeat every `p` bytes, each at a fixed bit position. Their byte offsets are computed once per factor. The eight single-bit masks depend only on `p mod 16`, so a `switch` selects them as compile-time constants.

### Faithfulness

All of a sieve's state lives in the `Sieve` struct. ISPC has no classes; a struct and functions that take it as their first argument are the nearest equivalent. Every pass creates a new instance and allocates its buffer at run time, sized from the sieve size. Nothing is precomputed or carried from one pass to the next, and no external dependency does any sieving.

### Parallelism

The multi-threaded runs start one pthread per thread, each running its own sieves. The program reports results for all, half and a quarter of the hardware threads, because SMT siblings share an L1 cache and fewer threads can finish more passes.

### Portability

On x86-64 the binary carries SSE4 and AVX2 code, and ISPC's dispatcher picks the path at start-up. On arm64 it compiles for NEON.

## How this was built

This solution came out of an experiment in agentic engineering with Claude (Anthropic). A Claude.ai session did the design, prototyping and coordination; a Claude Code session ran the benchmarks on Azure (AMD Zen 3, Zen 4 and Zen 5, and Arm Neoverse); the author set priorities and made the calls. Each change was self-tested with `PRIMES_TEST=1`, then timed in interleaved runs against the previous build and the leading solutions, and kept only if it won. The [`ispc-dev` branch of the author's fork](https://github.com/cauldnz/Primes/tree/ispc-dev/ispc-dev) holds the full record, including the regressions and dead ends.

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

`PRIMES_TEST=1 ./primes` checks the prime count for every power of ten from 10 to 10⁸ and some edge cases, prints the results and exits non-zero on any mismatch. `ISPC_TARGETS`, set for `build.sh` or as a Docker build argument, overrides the compile targets.

## Output

Intel Xeon at 2.8GHz, 2 vCPUs on a shared cloud instance, Ubuntu 24.04, ISPC 1.22.0:

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
