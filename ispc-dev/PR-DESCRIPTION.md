<!--
PR text for PlummersSoftwareLLC/Primes, target branch drag-race.
Title: [ISPC] Add ISPC solutions 1 (wheel) and 2 (base)
Code: hc/ispc-landing-4 (d2ef0d6), one commit on upstream drag-race c4e42f00 (#1095, the wheel
rules). Same code as hc/ispc-landing-2 (6cd85cd) and landing-3 (36a1616): landing-4 changes
comments only, and every object build.sh produces (plus both NEON targets) is byte-identical
to landing-3's. READMEs and source comments carry the 12 October cold-read fixes. solution_3
(the tables wheel) was dropped on 12 October; see LAUNCH-PLAN.md step 0.
Numbers: run 9 final scoreboard (STATUS.md, morning report of run ap-20261011T0645Z; logs in
results/hc/r9-final-wheel and r9-final-base, 6 rounds; solution_1 = "champ" rows of the wheel
logs, solution_2 = "cand" rows of the base logs). The READMEs use the same run 9 data (1T / all
threads, passes in 5 s). Official-results claims: results/leaderboard-2026-10-09b.md (PrimeView
API pull, 9 October).
Fill in #N once the F1/F2 issue is filed (LAUNCH-PLAN step 4). Replace the climb map URL if it
changes. Apply the house-style and economist-style skills to any edit. Everything below the
comment is the PR body.
-->

This PR adds the first two solutions in [ISPC](https://ispc.github.io/), Intel's Implicit SPMD Program Compiler:

- `PrimeISPC/solution_1`, a mod-30 wheel: `algorithm=wheel,faithful=yes,bits=1`;
- `PrimeISPC/solution_2`, the base algorithm: `algorithm=base,faithful=yes,bits=1`.

## How they were made

I designed and built a hill-climbing harness for this work: a bench on Azure that times each change against the previous build alongside paired controls, a keep rule, a gate that checks changes against the contribution rules, and a ledger of every result. Within it, Claude (Anthropic) ran unsupervised for long sessions, writing the code and running the experiments. I set the direction, decided the rules questions and reviewed the result, and I stand behind it.

The full story, change by change: [the climb map](https://cauldnz.github.io/agentic-hill-climber/), a page that charts every experiment and whether it was kept, with the raw record on the [`ispc-dev` branch of my fork](https://github.com/cauldnz/Primes/tree/ispc-dev/ispc-dev).

## The entries

Both programs are ISPC from end to end: the entry point, the timing loop, the threads, the sieve and the output. They call the C library only for the clock, memory, threads, the CPU count and affinity mask, environment variables, the error message on a wrong count (`write` to stderr) and `exit`. solution_2 also reads `/proc/cpuinfo` on AVX-512 machines, to tell Zen 5 apart. Results are printed with ISPC's own `print()`. Each has a self-test (`PRIMES_TEST=1`).

Each prints a line at one thread, then at all, half and a quarter of the hardware threads, and at four threads if that isn't already one of them. The four-thread line is there so the results are comparable with the four-thread lines other entries report; I'm happy to drop it.

**solution_1** stores the numbers coprime to 30 as eight bit-planes. Small primes are streamed into each plane as repeating word patterns, several primes per pass; large primes set single bits. The only primes it knows in advance are 2, 3 and 5 (the wheel) and 7, 11 and 13, whose patterns it builds in code on every pass. Every other prime is found in the sieve. The constant tables in the source describe only the wheel: its residues, the plane each maps to, and their inverses mod 30.

**solution_2** stores odd numbers only. It finds each factor by scanning the sieve and clears every multiple with its own single-bit OR in the source. Two details for review, both described in the README:

- Clearing starts at the period of the sieve that holds p². For factors below 128 that is the first period, so it also marks the smaller odd multiples of p and p itself, then restores p. Every bit is still set by its own single-bit OR in the source; the compiler merges the ORs that land in the same word, as LLVM does for mike-barber's Rust entry.
- On x86-64 the buffer isn't zeroed up front, because the pass for 3, always the first factor found, writes every word. That is worth about 1%, and I'm happy to restore the zeroing if you'd prefer.

On x86-64 each binary carries SSE4, AVX2 and AVX-512 code, and ISPC picks a path at start-up. On arm64 both compile for NEON.

## Results

Passes per second per thread, median of six interleaved rounds on Azure, 16 vCPUs (eight cores with SMT), except Cobalt 100 with four. 4T is the four-thread line, one thread per core. The READMEs give passes in five seconds, at one thread and at all threads.

Wheel, against danielspaangberg's `PrimeC/solution_2` (`5760of30030`), the fastest faithful wheel in the [official results](https://plummerssoftwarellc.github.io/PrimeView/) when I checked on 9 October:

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

In the same official results, mike-barber's Rust leads the faithful 1-bit base entries on every benchmark machine, with one exception: on the Threadripper at one thread, a Swift entry leads it by 3.4%. I had no Threadripper to test on.

## ISPC as a language

- Intel released ISPC as open source in 2011 and still maintains it ([source](https://github.com/ispc/ispc), [documentation](https://ispc.github.io/)).
- It is packaged in Debian and Ubuntu. Both Dockerfiles install Ubuntu 24.04's `ispc` package, so nothing is fetched from outside the distribution.
- It has users outside this repository: Unreal Engine's Chaos physics ([Intel article](https://www.intel.com/content/www/us/en/developer/articles/technical/unreal-engines-new-chaos-physics-system-screams-with-in-depth-intel-cpu-optimizations.html), [GDC talk](https://gdcvault.com/play/1026686/Intel-ISPC-in-Unreal-Engine)), Intel's Embree and OSPRay rendering libraries, and Open Image Denoise, whose CPU build [requires it](https://github.com/RenderKit/oidn).

## Notes

Two questions about the base rules are in #N. Nothing in this PR depends on them.

A third, table-built wheel was withdrawn after #1095.

## Contributing requirements

* [x] I read the contribution guidelines in CONTRIBUTING.md.
* [x] I placed my solution in the correct solution folder.
* [x] I added a README.md with the right badge(s).
* [x] I added a Dockerfile that builds and runs my solution.
* [x] I selected `drag-race` as the target branch.
* [x] All code herein is licensed compatible with BSD-3.
