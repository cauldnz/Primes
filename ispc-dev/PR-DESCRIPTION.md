<!--
PR text for PlummersSoftwareLLC/Primes, target branch drag-race.
Title: [ISPC] Add ISPC solutions 1 (wheel) and 2 (base)
Code: hc/ispc-landing-2 (6cd85cd), one commit on upstream drag-race c4e42f00 (#1095, the wheel
rules). solution_3 (the tables wheel) was dropped on 12 October; see LAUNCH-PLAN.md step 0.
Numbers: run 9 final scoreboard (STATUS.md, morning report of run ap-20261011T0645Z; logs in
results/hc/r9-final-wheel and r9-final-base, 6 rounds; solution_1 = "champ" rows of the wheel
logs, solution_2 = "cand" rows of the base logs). The READMEs' tables predate run 9 and must be
updated on the landing branch to match before the PR opens.
Fill in #N once the F1/F2 issue is filed (LAUNCH-PLAN step 4). Replace the climb map URL if it
changes. Apply the house-style and economist-style skills to any edit. Everything below the
comment is the PR body.
-->

This PR adds the first two solutions in [ISPC](https://ispc.github.io/), Intel's Implicit SPMD Program Compiler:

- `PrimeISPC/solution_1`, a mod-30 wheel: `algorithm=wheel,faithful=yes,bits=1`;
- `PrimeISPC/solution_2`, the base algorithm: `algorithm=base,faithful=yes,bits=1`.

Both programs are ISPC from end to end: the entry point, the timing loop, the threads, the sieve and the output. They call the C library only for the clock, memory allocation, pthreads and `getenv`. Each has a self-test (`PRIMES_TEST=1`). Each reports one thread, then all, half and a quarter of the hardware threads, plus a line at four threads.

## The entries

**solution_1** stores the numbers coprime to 30 as eight bit-planes. Small primes are streamed into each plane as repeating word patterns, several primes per pass; large primes set single bits. The only primes it knows in advance are 2, 3 and 5 (the wheel) and 7, 11 and 13, whose patterns it builds in code on every pass. Every other prime is found in the sieve. The constant tables in the source describe the wheel's residues and nothing else.

**solution_2** stores odd numbers only. It finds each factor by scanning the sieve and clears every multiple with its own single-bit OR in the source. For small factors the compiler merges a vector's ORs into one constant mask, as LLVM does for mike-barber's Rust entry. Two details for review, both described in the README. Dense clearing starts at the word that holds p², so p itself is marked and then restored. On x86-64 the buffer isn't zeroed up front, because the pass for 3, always the first factor found, writes every word. That is worth about 1%, and I'm happy to restore the zeroing if you'd prefer.

On x86-64 each binary carries SSE4, AVX2 and AVX-512 code, and ISPC picks a path at start-up. On arm64 both compile for NEON.

## Results

Passes per second per thread, the leaderboard's measure. Median of six interleaved rounds on Azure, 16 vCPUs (eight cores with SMT), except Cobalt 100 with four. 4T is the four-thread line, one thread per core.

Wheel, against danielspaangberg's `PrimeC/solution_2` (`5760of30030`), the fastest faithful wheel:

| CPU | solution_1 1T / 4T | danielspaangberg 1T | 1T ratio |
|---|---|---|---|
| AMD EPYC 7763 (Zen 3) | 23,758 / 23,143 | 7,872 | 3.0× |
| AMD EPYC 9V74 (Zen 4) | 26,274 / 26,124 | 8,994 | 2.9× |
| AMD EPYC 9V45 (Zen 5) | 46,718 / 46,541 | 14,009 | 3.3× |
| Azure Cobalt 100 (Neoverse N2) | 20,264 / 20,237 | 8,497 | 2.4× |

Base, against mike-barber's `PrimeRust/solution_1` (`bit-extreme-hybrid`):

| CPU | solution_2 1T / 4T | mike-barber 1T / 4T | 1T |
|---|---|---|---|
| AMD EPYC 7763 (Zen 3) | 11,210 / 11,186 | 10,502 / 10,516 | +6.7% |
| AMD EPYC 9V74 (Zen 4) | 16,585 / 16,565 | 15,327 / 15,323 | +8.2% |
| AMD EPYC 9V45 (Zen 5) | 27,811 / 25,903 | 25,231 / 23,535 | +10.2% |
| Azure Cobalt 100 (Neoverse N2) | 8,439 / 8,408 | 8,582 / 8,568 | −1.7% |

The Rust entry tops the official faithful 1-bit base results on all five runners, with one exception: on the Threadripper at one thread, a Swift entry leads it by 3.4%. I had no Threadripper to test on. The READMEs give passes in five seconds, all threads included.

## ISPC as a language

- Intel released ISPC as open source in 2011 and still maintains it ([source](https://github.com/ispc/ispc), [documentation](https://ispc.github.io/)).
- It is packaged in Debian and Ubuntu. Both Dockerfiles install Ubuntu 24.04's `ispc` package, so nothing is fetched from outside the distribution.
- It has users outside this repository: Unreal Engine's Chaos physics ([Intel article](https://www.intel.com/content/www/us/en/developer/articles/technical/unreal-engines-new-chaos-physics-system-screams-with-in-depth-intel-cpu-optimizations.html), [GDC talk](https://gdcvault.com/play/1026686/Intel-ISPC-in-Unreal-Engine)), Intel's Embree and OSPRay rendering libraries, and Open Image Denoise, whose CPU build [requires it](https://github.com/RenderKit/oidn).

## Notes

Two questions about the base rules are in #N. Nothing in this PR depends on them.

I also had a third entry, a wheel with tables built at compile time. I've left it out because it doesn't meet the new wheel rules (#1095).

How these were built: [the climb map](https://cauldnz.github.io/agentic-hill-climber/), with the full record on the [`ispc-dev` branch of my fork](https://github.com/cauldnz/Primes/tree/ispc-dev/ispc-dev).

## Contributing requirements

* [x] I read the contribution guidelines in CONTRIBUTING.md.
* [x] I placed my solution in the correct solution folder.
* [x] I added a README.md with the right badge(s).
* [x] I added a Dockerfile that builds and runs my solution.
* [x] I selected `drag-race` as the target branch.
* [x] All code herein is licensed compatible with BSD-3.
