<!--
PR text for PlummersSoftwareLLC/Primes, target branch drag-race.
Title: [ISPC] Add ISPC solutions: wheel (solution_1) and base (solution_2)
Results table filled on 2026-10-10 from results/hc/final4-wheel (hc/champion 059b8f3) and
final3-base (4c7dc69; base code unchanged since). hc/ispc-landing (77a197b) carries this code
onto ispc; land it before posting. Check every number
against ispc-dev/results/, and apply the house-style and economist-style skills to any edit.
Everything below the comment is the PR body.
-->

This PR adds the first two solutions in [ISPC](https://ispc.github.io/), Intel's Implicit SPMD Program Compiler. ISPC is an open-source, C-like language that Intel has maintained since 2011. Unreal Engine uses it for parts of its Chaos physics and animation code, and Intel's Embree and OSPRay rendering libraries use it. Both Dockerfiles install it from Ubuntu 24.04's `ispc` package, so there is no custom toolchain.

Both programs are written entirely in ISPC: the entry point, the timing loop, the pthreads, the sieve and the output. They call the C library only for the clock, memory allocation, threads and `getenv`.

## The two solutions

**solution_1** (`algorithm=wheel,faithful=yes,bits=1`) stores a mod-30 wheel as eight bit-planes. Small primes are streamed into each plane as repeating word patterns, eight primes per pass; large primes set single bits with scalar strides. On x86-64 one binary carries SSE4, AVX2 and AVX-512 code and picks a path at start-up. On arm64 it compiles for NEON.

**solution_2** (`algorithm=base,faithful=yes,bits=1`) stores odd numbers only and clears one composite per operation in the source. Its clearing routines follow mike-barber's Rust and GordonBGood's Chapel base solutions. One detail to flag for review: on x86-64 the buffer isn't zeroed up front, because the pass for 3, always the first prime the scan finds, writes every word. It's worth about 1%, the README describes it, and I'm happy to restore the explicit zeroing if you'd rather the set-up made no assumption about the first prime.

Both include a self-test (`PRIMES_TEST=1`) that checks the prime count at every power of ten up to 10⁸. Both report multi-threaded results at all, half and a quarter of the hardware threads.

## Why ISPC

A sieve's small primes produce dense bit patterns that repeat; its large primes produce scattered single bits. The first job suits SIMD and the second does not, so the two entries work as a small experiment.

In the wheel entry, ISPC vectorises the pattern streaming directly. The loop reads like scalar code, and the `uniform` and `varying` keywords show which values are shared across lanes. ISPC also exposes gang width, a setting C has no equivalent for: compiling for 16 program instances on 8-lane AVX2 (`avx2-i32x16`) was 12% to 16% faster than the natural width on Zen 3, Zen 4 and Zen 5.

The base entry has to clear one composite per operation, which seems to leave the lanes nothing to do. For small factors it doesn't: each composite's single-bit OR can be written in the lane that holds its word, and the compiler merges a vector's ORs into one constant mask, the same code LLVM's SLP vectoriser produces for mike-barber's Rust entry. That puts the base entry 7% ahead of the Rust entry on Zen 3 at one thread, 8% ahead on Zen 4 and 2% ahead on Zen 5, and 16% ahead on Zen 5 on all threads. On Cobalt 100 (arm64) it trails by 4%.

## Results

Passes in five seconds, median of six interleaved rounds, 16 vCPUs (eight cores with SMT):

| Machine | solution_1 1T / all | solution_2 1T / all | rogiervandam C 1T / all | mike-barber Rust 1T / all |
|---|---|---|---|---|
| AMD EPYC 7763 (Zen 3, AVX2) | 110,100 / 938,900 | 56,000 / 431,800 | 65,200 / 534,100 | 52,500 / 411,500 |
| AMD EPYC 9V74 (Zen 4, AVX-512) | 120,900 / 1,013,000 | 82,900 / 656,000 | 97,000 / 769,900 | 76,500 / 608,300 |
| AMD EPYC 9V45 (Zen 5, AVX-512) | 207,600 / 1,565,000 | 128,100 / 1,018,700 | 139,100 / 1,182,100 | 125,600 / 880,000 |
| Azure Cobalt 100 (Neoverse N2, 4 vCPUs) | 98,500 / 393,200 | 41,100 / 163,800 | n/a | 42,900 / 171,300 |

## How these were built

I built these as an experiment in agentic engineering with Claude (Anthropic). A Claude.ai session did the design, prototyping and coordination. A Claude Code session ran the benchmarks on Azure. I set the priorities and made the calls.

The method was hill-climbing against a fixed evaluation. Every change had to pass the self-test, then beat the previous build in interleaved runs, with rogiervandam's C running alongside as a control. Changes that lost were reverted and logged. The [`ispc-dev` branch of my fork](https://github.com/cauldnz/Primes/tree/ispc-dev/ispc-dev) holds the full record: the prototypes, every benchmark log, and the regressions and dead ends, from a first ISPC version at 6,300 passes to the submitted one. I'm happy to answer questions about any step.

## Contributing requirements

* [x] I read the contribution guidelines in CONTRIBUTING.md.
* [x] I placed my solution in the correct solution folder.
* [x] I added a README.md with the right badge(s).
* [x] I added a Dockerfile that builds and runs my solution.
* [x] I selected `drag-race` as the target branch.
* [x] All code herein is licensed compatible with BSD-3.
