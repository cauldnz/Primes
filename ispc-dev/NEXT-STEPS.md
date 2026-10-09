# Next steps for Claude Code (from the Claude.ai session)

**Last updated:** 2026-10-09 15:35 AEST. Living file; earlier versions are in
`git log -p ispc-dev/NEXT-STEPS.md`.

## Changes since last update

I read the target matrix from the raw logs in `results/azure-202610091438` to `…1501` (medians,
round 1 excluded on Zen 5). Decisions:

- **x86 targets are final:** `sse4-i32x8,avx2-i32x16,avx512skx-x16`. Wheel medians, 1T / 16T:

  | Machine | wheel | rogiervandam C5 | margin |
  |---|---|---|---|
  | Zen 3 (7763) | 81.6k / 704k | 65.2k / 532k | +25% / +32% |
  | Zen 4 (9V74) | 98.7k / 841k | 97.0k / 770k | +2% / +9% |
  | Zen 5 (9V45), AVX-512 | 150.9k / 1.25M | 133.4k / 1.20M | +13% / +4% |
  | Zen 5, AVX2 x16 only | 147.0k / 1.17M | 133.4k / 1.20M | +10% / −2% |

  `avx2-i32x16` closed most of the Zen 5 AVX2 gap (it was −7% / −18%). AVX-512 x16 adds 3% at
  1T and 6% at 16T on Zen 5, so it stays.
- **arm64 default is now `neon-i32x8`** in solution_1's `build.sh`: +4% on Neoverse N1, +15% on
  N2.
- **The Zen 5 "drift" was a warm-up effect.** Round 1 on `D16as_v7` runs about 17% slow for every
  build. HILL-CLIMB.md now discards round 1 everywhere.
- **The base entry trails.** mike-barber's Rust beats it by 15% on Zen 3, 17% on Zen 4 and 31%
  on Zen 5. I corrected solution_2's README and the PR body, which had implied parity. The
  base gap is now the top of the hill-climbing backlog.
- Gang-width figures in solution_1's README are now 12%, 14% and 16% (Zen 3, 4, 5).

## What to do now, in order

1. **Base hill-climb, time-boxed to about 60 minutes,** following HILL-CLIMB.md (base items 1–4).
   Profile first. Whatever base reaches in that hour goes in the PR.
2. **In parallel, PR prep (tasks 3 and 4 below):** final Output sections in both READMEs from
   the Zen runs, the results table in PR-DESCRIPTION.md, then the cherry-pick plan for `ispc`.
   Wheel numbers are settled unless a wheel experiment wins.
3. Report in STATUS.md with AEST times.

## Goal

Both ISPC entries PR-ready within about two hours:
- `PrimeISPC/solution_1` is the wheel entry.
- `PrimeISPC/solution_2` is the base-algorithm entry.

Do the steps in order and push results to `ispc-dev` as they land. Touching the `ispc` branch or
opening a PR still needs the user's explicit OK.

## What changed since your status report (pull first)

1. **Wheel: wider ISPC gangs** (commit `0b702ef`). The default x86 targets are now
   `sse4-i32x8,avx2-i32x16,avx512skx-x16`. On the sandbox Xeon (interleaved, passes in 5 s, 1T):

   | target | wheel 1T |
   |---|---|
   | avx2-i32x8 (old default) | 51.5–52.6k |
   | **avx2-i32x16** | **59.4–66.1k** |
   | avx512skx-x8 | 57.8–60.0k |
   | avx512skx-x16 | 55.4–57.6k |
   | avx512skx-x32 (ISPC 1.27) | 56.8–57.4k |
   | sse4-i32x4 / sse4-i32x8 | 36.8–37.5k / 41.8–44.2k |

   The likely reason: the dense loop streams `programCount` words per iteration, so 16 words
   means more independent loads and stores in flight and half the phase-wrap overhead.
   This is the prime suspect for the Zen 5 AVX2 gap. Mixed gang widths dispatch correctly in
   one binary. **Avoid `avx512skx-x32` with Ubuntu's ISPC 1.22**: it runs at about 23k.
2. **New base entry**, `solution_2` (commit `bdf7fda`): odds-only, one single-bit OR per
   composite in the source, after mike-barber's Rust and GordonBGood's Chapel.
   - Builds for `sse4-i32x4,avx2-i32x8` only: the AVX-512 target is ~18% slower for this
     scalar code.
   - Self-test passes for 13 sizes.
   - Sandbox: 29.5k 1T, vs mike-barber extreme-hybrid ~32.5k on the same box.
   - Already tried, no gain: dense limits of 192/256/384, 2× unrolled sparse loop,
     pointer-walking sparse loop.
3. **Both Dockerfiles take `--build-arg ISPC_TARGETS=...`**. `build.sh` also reads
   `ISPC_TARGETS` from the environment. Empty means the defaults.
4. ISPC 1.22 (Ubuntu) and 1.27 are within ~3% of each other. Compiler version is not a lever;
   stay on the distro package.

## Update after the rules review (pull again)

- `0a4e409`: both programs now report a wrong prime count on stderr (CONTRIBUTING wants
  non-result output there) and the base README title follows the template. Include it in the
  cherry-pick.
- `ispc-dev/RULES-REVIEW.md` has the full compliance check, a PR description draft
  and the remaining checklist. The user wants **one PR with both solutions**.
- Added to task 2: run the solution_2 arm64 build and self-test on Ampere. It's the one
  untested cell in the review.
- When you finalise targets in task 1, update solution_1's README portability paragraph to
  match.

## Update at 15:10: writing, README sections and the hill-climbing protocol

- **House style is mandatory.** Everything we publish follows Chris's `house-style` and
  `economist-style` skills (`~/.agents/skills/` on his machine): READMEs, the PR body, ledger
  notes and commit messages. Load both before writing. Australian English, no em-dash
  clauses, no "not X but Y" pivots, bold only for labels, a number or name behind every claim.
- **Both READMEs are rewritten** in house style, with "Why ISPC" and "How this was built"
  sections already in place. In task 3, only replace the Output sections with the final Zen
  numbers, and recheck the gang-width figures (11% on Zen 3, 14% on Zen 5) against the
  five-round medians.
- **The PR body is in `ispc-dev/PR-DESCRIPTION.md`.** Fill its results table from the final
  medians.
- **Hill climbing now follows `ispc-dev/HILL-CLIMB.md`**: hypothesis, plan, implement, gate,
  evaluate with controls in every round, ledger. Start with backlog item 1 (the Zen 5 drift
  from 150k to 126k). A sandbox A/B showed the stderr change did not cause it: old and new
  builds were within noise. PR readiness comes first; run the loop once tasks 3 and 4 are done,
  or alongside them if it doesn't block them.

## Tasks

### 1. Wheel target matrix on Zen 5 and Zen 3 (decides the default targets)

Build `solution_1` with `--build-arg ISPC_TARGETS=` set to each of the following. Run 3
interleaved rounds alongside C5, at 1T and all threads:
- `avx2-i32x8` (old baseline)
- `avx2-i32x16`
- `avx512skx-x8`
- `avx512skx-x16`

Decide:
- **Default AVX2 path:** almost certainly `avx2-i32x16`. Check that it closes the Zen 5 gap to
  C5 (138.7k / 1.18M), which is what runner 74 risks.
- **Whether to keep AVX-512:** if `avx2-i32x16` ≥ the best AVX-512 width on Zen 5, drop AVX-512
  from the defaults (`sse4-i32x8,avx2-i32x16`). Otherwise keep the faster AVX-512 width.

If time allows, also run a quick `PRIMES_DENSE_MAX` check at 192/256/320 with the chosen
targets, and an ARM run comparing `neon-i32x4` against `neon-i32x8`.

### 2. Base entry on Zen 3 and Zen 5

Run `solution_2` against `PrimeRust/solution_1` (mike-barber) and `PrimeChapel/solution_1`
(GordonBGood), at 1T and all threads. Optionally include `danielspaangberg_1of2` from
`PrimeC/solution_2`. This is only to set expectations; base is close to its floor (one
operation per composite), so don't spend long tuning it. Do confirm `ISPC_TARGETS` with and
without `avx512skx-x16` on Zen 5, to check the AVX-512 penalty holds there too.

### 3. README output sections

Update both READMEs' **Output** sections with the Zen 5 and Zen 3 runs, in the real output
format, stating machine, cores and ISPC version. Keep the self-test block. Make sure the
**Implementation** text still matches the final defaults (targets, threshold).

### 4. PR branch, after the user approves

- Rebase `ispc` onto current upstream `drag-race`.
- Cherry-pick the solution-only commits:
  - `83c20ec` (threshold 256, thread counts)
  - `0b702ef` (gangs)
  - `bdf7fda` (base)
  - the Dockerfile build-arg commit
  - the README updates
  - any target change from task 1
- Then verify:
  - `docker build` each solution with BuildKit
  - `tools/hadolint.sh ispc 1` and `tools/hadolint.sh ispc 2`
  - the self-tests pass
  - the outputs match the READMEs
- PR shape, for the user to decide:
  - **one PR adding both solutions** (one language-eligibility discussion), or
  - two PRs.

  Title starts with `[ISPC]`; target `drag-race` on PlummersSoftwareLLC/Primes.
