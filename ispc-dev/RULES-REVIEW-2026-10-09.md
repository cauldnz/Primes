# CONTRIBUTING.md review for the ISPC PR, 2026-10-09

The plan is one PR adding both solutions:

- `PrimeISPC/solution_1`: wheel, faithful, 1 bit
- `PrimeISPC/solution_2`: base, faithful, 1 bit

Checked against `CONTRIBUTING.md` at upstream `drag-race` a2899c9 (3 Oct 2026), the PR
template, `.github/workflows/CI.yml` and `tools/src/commands/benchmark.ts`.

## Checklist

| Requirement | solution_1 (wheel) | solution_2 (base) |
|---|---|---|
| Folder `Prime<Language>/solution_<n>`, new language starts at 1 | ✅ | ✅ |
| README: `# <Language> solution by <user>`, description, run instructions, output | ✅ | ✅ (title fixed in 33291eb) |
| Badges match tags | ✅ wheel/yes/1 | ✅ base/yes/1 |
| Dockerfile base image | ✅ ubuntu:24.04 (no official ISPC image; Alpine only in edge) | ✅ same |
| `AS build` stage when build needs more than run | ✅ | ✅ |
| No binary dependencies, no fetched toolchains | ✅ distro `ispc` package | ✅ |
| hadolint with `config/hadolint.yml` | ✅ locally; run `tools/hadolint.sh ispc 1` | ✅ locally; run `tools/hadolint.sh ispc 2` |
| amd64 and arm64 | ✅ NEON verified on Ampere | ⚠️ NEON build **not yet run on arm64** |
| Output `label;iterations;total_time;threads;tags` | ✅ | ✅ |
| Label contains username | ✅ `cauldnz-ispc` | ✅ `cauldnz-ispc-base` |
| `en_US` decimal, tags ≤32 chars, no spaces | ✅ | ✅ |
| Other output on stderr | ✅ since 33291eb (error path); self-test is opt-in only | ✅ |
| Sieve of Eratosthenes | ✅ | ✅ |
| Returns the result | ✅ the is_prime bit array (inverted), kept in the struct | ✅ same |
| Runs ≥5 s, stops promptly | ✅ deadline checked every pass | ✅ |
| All primes up to 1,000,000 | ✅ self-test 10..10^8 | ✅ self-test 13 sizes |
| BSD-3 compatible | ✅ our own code; tick the template box | ✅ |
| Labels accurate (rejection risk) | ✅ wheel: mod-30 wheel storage | ✅ base, see below |

## Faithfulness (both)

- **No external dependencies:** only libc (allocation, clock, pthreads).
- **Class equivalent:** all state is in `struct Sieve`, which ISPC uses in place of a class. For
  the wheel entry this includes the pattern scratch. `static const` tables (residues, inverses)
  are constants, not state.
- **Fresh instance per pass:** each pass allocates a new instance at run time, sized from the
  sieve size. Nothing is kept between passes.

## Base algorithm (solution_2), point by point

- **Outer loop:** find the next prime by checking odd numbers sequentially from 3, then clear
  its multiples, and stop at sqrt. ✅
- **Clearing:**
  - Each odd multiple is cleared individually, in increasing order (step 2p in numbers, p in
    bits). ✅
  - In the source, every composite gets its own single-bit OR. GordonBGood's README is explicit
    that one mask clearing several composites was refused as base.
  - Constant-offset ORs that LLVM merges in codegen are the accepted precedent: the
    mike-barber Rust dense/sparse resetters and the GordonBGood Chapel dense/extreme ones.
- **Start point:** clearing begins at the chunk containing p², which also re-marks some
  multiples between 3p and p². The original implementation started at 3p, so this is within
  it. p itself is restored. ✅
- **No prime knowledge:** dense cases cover every odd factor below 128, including 9, 15 and so
  on, so nothing beyond "2 is the only even prime" is assumed. ✅
- **No page segmentation:** primes are not determined by a separate first step. ✅

## Wheel algorithm (solution_1)

The wheel definition covers it: storage is the mod-30 wheel, and the 7·11 tile is a
precalculated pattern projected onto the sieve. Pattern ORs that set several bits are fine
here, because the one-operation-per-composite rule belongs to the *base algorithm*, not to
faithfulness. Spångberg's wheel entries are the faithful precedent.

A reviewer could argue for "other", because of the pattern-streaming technique. If asked,
retagging is a one-line change, but wheel is the honest primary characteristic.

## Language eligibility (the maintainers' main judgement call)

The criteria are met: an independent, public, Intel-maintained open-source compiler since
2011, with releases, docs and distro packages (Ubuntu/Debian, Alpine, Homebrew), and real use:

- [GDC talk: Intel ISPC in Unreal Engine](https://gdcvault.com/play/1026686/Intel-ISPC-in-Unreal-Engine)
- [Intel: Unreal Engine's Chaos physics optimised with ISPC](https://www.intel.com/content/www/us/en/developer/articles/technical/unreal-engines-new-chaos-physics-system-screams-with-in-depth-intel-cpu-optimizations.html)
- Intel's Embree and OSPRay rendering libraries

**Risk: "general-purpose enough".** ISPC is usually used for kernels called from C/C++. Both
entries keep *everything* in ISPC, including `main`, timing, threads and output, as the
"honest representation" rule requires. The PR should say so up front, and say that the libc
calls are the same kind every C entry makes.

## Disclosure

Development was AI-assisted (Claude), and the commits carry `Co-Authored-By` trailers. Nothing
in CONTRIBUTING forbids this. Its AI clause targets AI-generated *languages*. But maintainers
judge "genuine, good-faith effort", so a short, upfront note plus the verification artefacts
(self-tests, interleaved benchmark logs) is the safer posture. **The user's call.**

## "Other" lane

It is open, but not competitive today. An odds-only fused-pattern design (`prototypes/sieve2.ispc`)
measured against rogiervandam's C on the sandbox, 3 interleaved rounds, 1T:

| | passes |
|---|---|
| sieve2, AVX2 x16 | ~47k |
| rogiervandam (C) | ~56k |
| our wheel | ~62k |

Beating rogiervandam in "other" would need cache blocking on the 62 KB odds-only array.
That's a candidate follow-up PR (solution_3), not part of this one.

## Remaining before the PR

1. Final target set for solution_1 (Zen 5 matrix, NEXT-STEPS task 1). Update its README
   portability paragraph to match.
2. Run the arm64 build and self-test of solution_2 on Ampere.
3. Put Zen output in both READMEs.
4. Rebase `ispc` on upstream, cherry-pick the solution-only commits, then run `docker build`
   with BuildKit and `tools/hadolint.sh ispc 1` / `ispc 2`.
5. Get the user's OK, then open the PR with the description below.

## PR description draft

> **[ISPC] Add ISPC solutions: wheel (solution_1) and base (solution_2)**
>
> This adds the first solutions in [ISPC](https://ispc.github.io/), the Intel® Implicit SPMD
> Program Compiler, an open-source C-like SPMD language maintained by Intel since 2011 and
> used in production in Unreal Engine (Chaos physics, animation) and in Intel's Embree and
> OSPRay. It is installed from Ubuntu 24.04's `ispc` package; no custom toolchain.
>
> Both programs are written entirely in ISPC (entry point, timing loop, pthreads, sieve and
> output). They only call the C library, for the clock, allocation and threads.
>
> - **solution_1**: `algorithm=wheel,faithful=yes,bits=1`. A mod-30 wheel stored as 8
>   bit-planes; small primes are streamed into each plane as repeating word patterns with
>   SIMD; large primes use strided bit sets. Multi-target x86-64 binary (SSE4/AVX2/AVX-512,
>   runtime dispatch), NEON on arm64.
> - **solution_2**: `algorithm=base,faithful=yes,bits=1`. Odds-only, one single-bit operation
>   per composite in the source, after the mike-barber (Rust) and GordonBGood (Chapel) base
>   solutions.
>
> Both have a self-test (`PRIMES_TEST=1`) that checks prime counts up to 10^8. Multi-threaded
> results are reported at all, half and a quarter of the hardware threads.
>
> [Optional disclosure line: Developed with AI assistance (Claude); all results were measured
> on real hardware, and benchmark logs are available on request.]
>
> * [x] I read the contribution guidelines in CONTRIBUTING.md.
> * [x] I placed my solution in the correct solution folder.
> * [x] I added a README.md with the right badge(s).
> * [x] I added a Dockerfile that builds and runs my solution.
> * [x] I selected `drag-race` as the target branch.
> * [x] All code herein is licensed compatible with BSD-3.
