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

The multiples of a prime `p` that fall in one plane step through it with stride `p`, so each plane is a small, regular sieve of its own. A modular inverse mod 30 gives the first multiple in each plane; for primes below 10,000 that first multiple comes from a table generated at build time (see Faithfulness).

### Small primes stream repeating patterns

A stride-`p` bit pattern repeats every `p` 64-bit words. Because 64 is invertible modulo any odd `p`, every bit offset of the pattern is a whole-word rotation of one base pattern. Each prime below 1,024 therefore has one base pattern, shared by all eight planes, generated at build time together with its starting rotation in each plane. The SIMD lanes then stream the pattern into the sieve with contiguous vector loads. The hot loop has no gathers and no divisions.

Several primes are fused into one pass over a plane, so each sieve word is loaded and stored once per group: six primes with AVX-512, eight otherwise (six was 4% to 5% faster at one thread on Zen 4 and Zen 5 with AVX-512, and 1% slower on Zen 3 with AVX2). Every member of a group starts at the first word any member touches, so no member needs a lead-in of its own. Members then also mark their multiples below `p²`, which are composite, and `p` itself, which is cleared again afterwards. A group of one prime skips the fused loop. The loop keeps one index into the pattern table per member and wraps it with a single conditional subtract. With AVX-512 the loop takes two vectors (32 words) per iteration, so each member's phase update is paid half as often. Those full vectors run unmasked.

### Wheel tile

Multiples of 7 and 11 repeat every 77 words in every plane. That period is generated for each plane at build time, and each pass writes the plane in one pass over it: each word is a tile word ORed with the matching word of 13's pattern. Afterwards every bit below 17² is final. Folding 13 into the copy saves a separate read-modify-write pass over the 33KB of planes.

### Large primes

Primes above 256 (the default) set at most one bit per word. They use scalar strided bit-setting, with all eight planes advanced in one loop to keep eight independent memory streams busy. The bit indices are 64-bit and the build uses ISPC's `--addressing=64`, so each composite costs four instructions, with no sign extensions and no register spills.

### Faithfulness

All of a sieve's state lives in the `Sieve` struct. ISPC has no classes; a struct and functions that take it as their first argument are the nearest equivalent. Every pass creates a new instance and allocates its buffers at run time, sized from the sieve size. Nothing is carried from one pass to the next, and no external dependency does any sieving.

As a wheel may start from "a (pre)calculated set of prime numbers within a certain base number range" (and as `PrimeZig/solution_3` builds its tables at compile time), `build.sh` first compiles and runs a small C generator, `gen_tables.c`, that writes read-only constant tables into a header the ISPC source includes. For each prime from 17 up to 10,000 (the square root of 10^8) it records the first bit at or after `p²` in each of the eight planes, as a 16-bit offset from `p²/30` (19,568 bytes). For each prime from 17 up to 1,024 (the largest prime handled as a word pattern) it records the stride-`p` word pattern, extended by 32 words, and its starting rotation in each plane (about 685KB of patterns, 3.6KB of offsets; at the default 256 a pass reads about 60KB of them). It also stores the 77-word 7×11 tile of each plane and 13's pattern (7.6KB). None of this depends on the sieve size. Every pass still allocates a new sieve and sieves it from scratch, finding the primes up to `sqrt(n)` from the sieve itself; the tables only replace the start-offset arithmetic and pattern building each pass used to repeat. A prime beyond the table (needed from 10,007², just above 10^8) falls back to computing its start offsets at run time, so every sieve size works.

### Parallelism

The multi-threaded runs start one pthread per thread, each running its own sieves, and SIMD runs within every thread. The program reports results for all, half and a quarter of the hardware threads (the CPUs in its affinity mask, so a container limited with `--cpuset-cpus` is not oversubscribed), because SMT siblings share an L1 cache and fewer threads can finish more passes.

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
| AMD EPYC 7763 (Zen 3, AVX2), 16 threads | 110,100 / 938,900 | 38,100 / 309,000 | 65,200 / 534,100 | 2.9× / 3.0×; +69% / +76% |
| AMD EPYC 9V74 (Zen 4, AVX-512), 16 threads | 120,900 / 1,013,000 | 45,000 / 372,400 | 97,000 / 769,900 | 2.7× / 2.7×; +25% / +32% |
| AMD EPYC 9V45 (Zen 5, AVX-512), 16 threads | 207,600 / 1,565,000 | 70,300 / 503,300 | 139,100 / 1,182,100 | 3.0× / 3.1×; +49% / +32% |
| Azure Cobalt 100 (Neoverse N2), 4 threads | 98,500 / 393,200 | 42,700 / 169,600 | n/a | 2.3× / 2.3× |

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
