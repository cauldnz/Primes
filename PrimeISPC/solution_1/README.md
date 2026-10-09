# ISPC solution by cauldnz

![Algorithm](https://img.shields.io/badge/Algorithm-wheel-yellowgreen)
![Faithfulness](https://img.shields.io/badge/Faithful-yes-green)
![Parallelism](https://img.shields.io/badge/Parallel-yes-green)
![Bit count](https://img.shields.io/badge/Bits-1-green)

A sieve of Eratosthenes on a mod-30 wheel, written in [ISPC](https://ispc.github.io/), Intel's Implicit SPMD Program Compiler. ISPC is a C-like language in which ordinary-looking code runs across every SIMD lane at once. The whole program is ISPC: the entry point, the timing loop, the threads, the sieve and the output. It calls the C library only for the clock, memory allocation, pthreads and `getenv`.

[solution_2](../solution_2) is the base-algorithm companion to this entry.

## Why ISPC

The small primes are where a sieve spends its effort, and their multiples form dense bit patterns that repeat. The large primes set scattered single bits. ISPC suits the first job. The pattern-streaming loop below is written once, as scalar-looking code, and the compiler spreads it across the vector lanes. The `uniform` and `varying` keywords show which values are shared across lanes and which differ per lane, so the cost of each line is visible in the source.

One build covers every machine the benchmark runs on. On x86-64 the binary carries SSE4, AVX2 and AVX-512 code, and ISPC's dispatcher picks the best path the CPU supports at start-up. On arm64 it compiles for NEON. The official runners range from an SSE4-only Celeron to an AVX-512 Zen 5 Threadripper and a Raspberry Pi 4.

ISPC also has a tuning knob C lacks: gang width, the number of program instances that run together. Compiling for 16 instances on 8-lane AVX2 hardware (`avx2-i32x16`) was 12% faster on Zen 3, 14% on Zen 4 and 16% on Zen 5 than the natural width, because each loop iteration keeps more independent loads and stores in flight. On arm64, `neon-i32x8` beat `neon-i32x4` by 4% on Neoverse N1 and 15% on Neoverse N2.

## Implementation

### Storage

Only numbers coprime to 30 are stored, in eight bit-planes, one per residue `R` in {1, 7, 11, 13, 17, 19, 23, 29}. Bit `m` of plane `R` stands for `30m + R`, and a set bit means composite. Up to 1,000,000 the planes take 8 × 521 64-bit words, about 33KB.

### Each plane is a stride sieve

The multiples of a prime `p` that fall in one plane step through it with stride `p`, so each plane is a small, regular sieve of its own. A modular inverse mod 30 gives the first multiple in each plane.

### Small primes stream repeating patterns

A stride-`p` bit pattern repeats every `p` 64-bit words. Because 64 is invertible modulo any odd `p`, every bit offset of the pattern is a whole-word rotation of one base pattern. Each prime therefore builds one base pattern, shared by all eight planes, plus a 64-entry table of starting rotations, filled while the pattern is built. The SIMD lanes then stream the pattern into the sieve with contiguous vector loads. The hot loop has no gathers and no divisions.

Several primes are fused into one pass over a plane, so each sieve word is loaded and stored once per group: six primes with AVX-512, eight otherwise (six was 4% to 5% faster at one thread on Zen 4 and Zen 5 with AVX-512, and 1% slower on Zen 3 with AVX2). Every member of a group starts at the first word any member touches, so no member needs a lead-in of its own. Members then also mark their multiples below `p²`, which are composite, and `p` itself, which is cleared again afterwards. 13 is the one prime that runs alone and skips the fused loop. Each member's pattern sits in a fixed row of the group's buffer, so the loop keeps only a phase per member in a register; reading the patterns through a pointer per member ran out of registers on x86 and cost 2% to 3% at all threads.

### Wheel tile

Multiples of 7 and 11 repeat every 77 words in every plane. The program builds that period once and copies it along each plane with vector copies. Then 13 runs on its own, after which every bit below 17² is final.

### Large primes

Primes above 256 (the default) set at most one bit per word. They use scalar strided bit-setting, with all eight planes advanced in one loop to keep eight independent memory streams busy. The bit indices are 64-bit and the build uses ISPC's `--addressing=64`, so each composite costs four instructions, with no sign extensions and no register spills.

### Faithfulness

All of a sieve's state, including its pattern scratch space, lives in the `Sieve` struct. ISPC has no classes; a struct and functions that take it as their first argument are the nearest equivalent. Every pass creates a new instance and allocates its buffers at run time, sized from the sieve size. Nothing is precomputed or carried from one pass to the next, and no external dependency does any sieving.

### Parallelism

The multi-threaded runs start one pthread per thread, each running its own sieves, and SIMD runs within every thread. The program reports results for all, half and a quarter of the hardware threads, because SMT siblings share an L1 cache and fewer threads can finish more passes.

### Two lessons for ISPC users

- **Hidden divides.** A phase-wrapping loop written as `while (r >= p) r -= p;` compiled to a hardware integer division on every iteration. In an early version it cost about two-thirds of the run time. Making the pattern period at least one vector step long reduced the wrap to a single conditional subtract.
- **Functions that aren't inlined get an execution mask too.** ISPC compiles a non-inlined `static` function for an unknown mask, so every vector load and store inside it is masked, even when every caller runs with all lanes on. On AVX2 a masked store is slow on Zen 2 to Zen 4. The fused loop runs in an `unmasked` block, and without AVX-512 the last partial vector of a plane runs on into padding instead of being masked: the extra words get the same prime's pattern, which is correct for them.
- **`export` functions handed to pthreads need `unmasked`.** The address of an `export` function points at ISPC's internal variant, which expects a hidden execution-mask argument. `pthread_create` passes whatever happens to be in that register, so the thread can run with every SIMD lane switched off. Wrapping the thread body in `unmasked { ... }` turns the lanes on.

## How this was built

This solution came out of an experiment in agentic engineering with Claude (Anthropic). A Claude.ai session did the design, prototyping and coordination; a Claude Code session ran the benchmarks on Azure (AMD Zen 3, Zen 4 and Zen 5, and Arm Neoverse); the author set priorities and made the calls. Each change was self-tested with `PRIMES_TEST=1`, then timed in interleaved runs against the previous build and the leading solutions, and kept only if it won. The [`ispc-dev` branch of the author's fork](https://github.com/cauldnz/Primes/tree/ispc-dev/ispc-dev) holds the full record, including the regressions and dead ends.

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

### Options

- `PRIMES_TEST=1` checks the prime count for every power of ten from 10 to 10⁸, prints the results and exits non-zero on any mismatch.
- `PRIMES_DENSE_MAX=<n>` sets the size below which primes are applied as word patterns rather than single bits. The default, 256, was fastest on Zen 3 and Zen 5.
- `ISPC_TARGETS`, set for `build.sh` or as a Docker build argument, overrides the compile targets.

## Output

AMD EPYC 9V45 (Zen 5), 16 vCPUs, Azure `Standard_D16as_v7`, Ubuntu 24.04, ISPC 1.22.0, in Docker:

```
cauldnz-ispc;191112;5.000023;1;algorithm=wheel,faithful=yes,bits=1
cauldnz-ispc;1467424;5.000176;16;algorithm=wheel,faithful=yes,bits=1
cauldnz-ispc;1399782;5.000106;8;algorithm=wheel,faithful=yes,bits=1
cauldnz-ispc;756188;5.000046;4;algorithm=wheel,faithful=yes,bits=1
```

Passes in 5 seconds against danielspaangberg's fastest faithful wheel (PrimeC/solution_2,
`5760of30030`) and rogiervandam's C (PrimeC/solution_5), measured in the same interleaved
rounds on Azure Spot nodes, median of six rounds, one thread / all threads:

| CPU | this entry | danielspaangberg (wheel) | rogiervandam C | lead over each |
|---|---|---|---|---|
| AMD EPYC 7763 (Zen 3, AVX2), 16 threads | 99,800 / 882,100 | 38,100 / 308,100 | 65,100 / 535,200 | 2.6× / 2.9×; +53% / +65% |
| AMD EPYC 9V74 (Zen 4, AVX-512), 16 threads | 116,600 / 982,200 | 45,300 / 372,500 | 97,100 / 769,900 | 2.6× / 2.6×; +20% / +28% |
| AMD EPYC 9V45 (Zen 5, AVX-512), 16 threads | 182,700 / 1,480,000 | 66,600 / 500,500 | 133,600 / 1,210,000 | 2.7× / 3.0×; +37% / +24% |
| Azure Cobalt 100 (Neoverse N2), 4 threads | 94,200 / 376,400 | 42,500 / 169,600 | n/a | 2.2× / 2.2× |

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
