# ISPC solution by cauldnz

![Algorithm](https://img.shields.io/badge/Algorithm-base-green)
![Faithfulness](https://img.shields.io/badge/Faithful-yes-green)
![Parallelism](https://img.shields.io/badge/Parallel-yes-green)
![Bit count](https://img.shields.io/badge/Bits-1-green)

A sieve of Eratosthenes that follows the base algorithm, written in [ISPC](https://ispc.github.io/), Intel's Implicit SPMD Program Compiler. The whole program is ISPC: the entry point, the timing loop, the threads, the sieve and the output. It calls the C library only for the clock, memory allocation, pthreads and `getenv`.

[solution_1](../solution_1) is the wheel companion to this entry.

## Why ISPC, for the base algorithm

This entry is the counterpoint to solution_1. The base algorithm clears one composite per
operation, which seems to leave the vector lanes nothing to share. For small factors it
doesn't: each composite's single-bit OR can be written in the SIMD lane that holds its word,
and with the factor and lane known at compile time the compiler merges a vector's ORs into one
constant mask. mike-barber's Rust entry gets the same code from LLVM's SLP vectoriser without
asking; ISPC needs it written out, and writing per-lane code is what ISPC is for. That change
took this entry from 15% to 31% behind the Rust entry to 6% ahead on Zen 3 and Zen 4, within
3% on Zen 5 at one thread and 14% ahead there on all threads (results below).

## Implementation

### Storage

One bit per odd number: bit `i` stands for `2i + 1`, and a set bit means composite.

On x86-64 the program doesn't zero the whole buffer before sieving. It zeroes word 0, so the scan can read the bit for 3. The scan always finds 3 first, and the pass for 3 writes every word of the sieve instead of reading and updating it: it sets the multiples of 3 and clears every other bit in the same sweep. That saves one pass over the buffer, worth about 1% at one thread. The arm64 build zeroes the buffer first, because its pass for 3 is the scalar routine.

### The base algorithm

An outer loop finds the next prime by scanning for the next clear bit, then clears that prime's odd multiples, stepping `2 × factor` through the numbers (`factor` through the bits). It stops at the square root of the sieve size. In the source, every composite is cleared by its own single-bit OR; no operation clears two composites. The clearing routines follow mike-barber's Rust solution ([PrimeRust/solution_1](../../PrimeRust/solution_1)) and GordonBGood's Chapel solution ([PrimeChapel/solution_1](../../PrimeChapel/solution_1)).

- **Factors below 128.** The odd multiples of `p` repeat with a period of `p` 64-bit words, and each period holds exactly 64 multiples at fixed word and bit offsets. A `switch` over the factor calls an inlined routine with the factor as a compile-time constant, so the compiler turns those offsets and single-bit masks into immediates. For factors below 119 the routine works on blocks of `programCount` periods, one vector of consecutive words at a time: each composite's single-bit OR is applied in the lane that holds its word, and the compiler folds a vector's ORs into one constant. Clearing starts at the period that contains `p²`. The smaller multiples in that period are composite too; only `p` itself is restored afterwards. Every odd factor has a case, including 9, 15 and the other composites, so the clearing routines assume nothing about which numbers are prime beyond 2 being the only even one. The set-up described under Storage is the one place where the program relies on 3 being the first prime. On arm64 the routine stays scalar: with two 64-bit lanes per NEON register the vector form was no faster.
- **Factors of 128 and above.** The same idea over bytes: eight multiples repeat every `p` bytes, each at a fixed bit position. Their byte offsets are computed once per factor, and a pointer walks over the `p`-byte chunks, so each composite costs one OR instruction. The eight single-bit masks depend only on `p mod 16`, so a `switch` selects them as compile-time constants.

### Faithfulness

All of a sieve's state lives in the `Sieve` struct. ISPC has no classes; a struct and functions that take it as their first argument are the nearest equivalent. Every pass creates a new instance and allocates its buffer at run time, sized from the sieve size. Nothing is precomputed or carried from one pass to the next, and no external dependency does any sieving.

### Parallelism

The multi-threaded runs start one pthread per thread, each running its own sieves. The program reports results for all, half and a quarter of the hardware threads, because SMT siblings share an L1 cache and fewer threads can finish more passes.

### Portability

On x86-64 the binary carries SSE4, AVX2 and AVX-512 code (`sse4-i32x4,avx2-i32x8,avx512skx-x8`), and ISPC's dispatcher picks the path at start-up. Wider gangs (`avx2-i32x16`, `avx512skx-x16`) stopped the compiler folding the dense masks and ran far slower. On arm64 it compiles for NEON.

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

AMD EPYC 9V45 (Zen 5), 16 vCPUs, Azure `Standard_D16as_v7`, Ubuntu 24.04, ISPC 1.22.0, in Docker:

```
cauldnz-ispc-base;122668;5.000019;1;algorithm=base,faithful=yes,bits=1
cauldnz-ispc-base;994403;5.000215;16;algorithm=base,faithful=yes,bits=1
cauldnz-ispc-base;867139;5.000108;8;algorithm=base,faithful=yes,bits=1
cauldnz-ispc-base;458802;5.000046;4;algorithm=base,faithful=yes,bits=1
```

Passes in 5 seconds against mike-barber's Rust (PrimeRust/solution_1, `bit-extreme-hybrid`)
and davepl's C++ (PrimeCPP/solution_5), measured in the same interleaved rounds on Azure Spot
nodes, median of five rounds, one thread / all threads:

| CPU | this entry | mike-barber Rust | davepl C++ |
|---|---|---|---|
| AMD EPYC 7763 (Zen 3, AVX2) | 58,100 / 428,000 | 55,100 / 411,900 | 38,400 / 307,100 |
| AMD EPYC 9V74 (Zen 4, AVX-512) | 81,400 / 649,800 | 76,600 / 607,800 | 60,600 / 483,700 |
| AMD EPYC 9V45 (Zen 5, AVX-512) | 122,700 / 996,000 | 126,400 / 876,000 | 92,300 / 712,300 |
| Azure Cobalt 100 (Neoverse N2, 4 vCPUs) | 41,100 / 164,000 | 42,900 / 171,300 | 32,200 / 128,600 |

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
