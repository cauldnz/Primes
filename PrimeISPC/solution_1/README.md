# ISPC solution by cauldnz

![Algorithm](https://img.shields.io/badge/Algorithm-wheel-yellowgreen)
![Faithfulness](https://img.shields.io/badge/Faithful-yes-green)
![Parallelism](https://img.shields.io/badge/Parallel-yes-green)
![Bit count](https://img.shields.io/badge/Bits-1-green)

A sieve of Eratosthenes written in [ISPC](https://ispc.github.io/), the Intel® Implicit SPMD Program Compiler: a C-like language in which ordinary-looking code runs across all SIMD lanes at once. The entire program is ISPC — the entry point, the timing loop, thread management, the sieve and the output. The only external calls are to the C library (`clock_gettime`, `aligned_alloc`/`free`, pthreads, `getenv`).

## Implementation

**Storage: a mod-30 wheel, 1 bit per candidate.** Only numbers coprime to 30 are stored, as 8 bit-planes, one per residue `R ∈ {1, 7, 11, 13, 17, 19, 23, 29}`. Bit `m` of plane `R` represents `30m + R`; a set bit means composite. Up to 1,000,000 this is 8 × 521 64-bit words, about 33 KB, which fits in L1 cache.

**Every plane is an ordinary stride sieve.** The multiples of a prime `p` that land in one plane form a progression with stride `p`, so the 8 planes are 8 small, regular sieves. Its first bit in each plane is found with a modular inverse mod 30.

**Small primes are streamed as repeating word patterns.** A stride-`p` bit pattern repeats every `p` 64-bit words. Because 64 is invertible modulo an odd `p`, every bit offset of the pattern is just a whole-word rotation of one base pattern. So each prime gets one base pattern, shared by all 8 planes, plus a 64-entry table (filled while building the pattern) giving the starting rotation for any offset. The SIMD lanes then stream the pattern into the sieve with contiguous vector loads: no gathers, and no divisions in the hot loop.

**Patterns are fused.** Up to 8 primes' patterns are OR-ed into each plane in a single pass, so each sieve word is loaded and stored once per 8 primes.

**Wheel tile.** Multiples of 7 and 11 repeat every 77 words in every plane, so that period is built once and copied along each plane with vector copies. 13 follows on its own, after which every bit below 17² is final.

**Large primes** (above 384) set at most one bit per word, so they use scalar strided bit-setting, with all 8 planes advanced in one loop to give 8 independent memory streams.

**Faithfulness.** All of a sieve's state, including its pattern scratch space, lives in the `Sieve` struct (ISPC has no classes; a struct with functions taking it as their first argument is the closest equivalent). A new instance is created and its buffers allocated, sized from the sieve size at run time, on every pass. Nothing is precomputed or carried between passes, and there are no external dependencies.

**Parallelism.** The multi-threaded run starts one pthread per hardware thread, each running independent sieves. SIMD is used within every thread.

**Portability.** On x86-64 the build compiles SSE4, AVX2 and AVX-512 versions into one binary, and ISPC's built-in dispatcher picks the best one the CPU supports when the program starts. On ARM64 the build targets NEON.

### Two ISPC lessons worth passing on

- **Watch for hidden divides.** A phase-wrapping loop written as `while (r >= p) r -= p;` was compiled by LLVM into a hardware integer division on every iteration, which cost roughly two thirds of the run time in an early version. Replacing it with a single conditional subtract (by making the pattern period at least as long as one vector step) removed it.
- **`export` functions passed to pthreads need `unmasked`.** Taking the address of an `export` function yields ISPC's internal variant, which expects a hidden execution-mask argument. `pthread_create` passes whatever is in that register, so the code can run with every SIMD lane silently switched off. Wrapping the thread body in `unmasked { ... }` turns all lanes on.

## Run instructions

### Docker

```
docker build -t primes-ispc .
docker run --rm primes-ispc
```

### Native (Ubuntu 24.04)

```
sudo apt-get install ispc gcc
sh build.sh
./primes
```

### Optional environment variables

- `PRIMES_TEST=1` checks the prime count for every power of ten from 10 to 10⁸, prints the results, and exits non-zero on any mismatch.
- `PRIMES_DENSE_MAX=<n>` sets the threshold below which primes are applied as word patterns instead of individual bits (default 384).

## Output

Intel Xeon @ 2.80 GHz, 2 vCPUs (shared cloud instance), Ubuntu 24.04, ISPC 1.22.0, AVX-512 code path:

```
cauldnz-ispc;56457;5.000051;1;algorithm=wheel,faithful=yes,bits=1
cauldnz-ispc;107784;5.000350;2;algorithm=wheel,faithful=yes,bits=1
```

Self-test:

```
size 10 -> 4 primes (expected 4) 1
size 100 -> 25 primes (expected 25) 1
size 1000 -> 168 primes (expected 168) 1
size 10000 -> 1229 primes (expected 1229) 1
size 100000 -> 9592 primes (expected 9592) 1
size 1000000 -> 78498 primes (expected 78498) 1
size 10000000 -> 664579 primes (expected 664579) 1
size 100000000 -> 5761455 primes (expected 5761455) 1
```
