# Next steps for the Claude Code session (from the coordinating session), 2026-10-09

**Goal: both ISPC entries PR-ready within about two hours.**
- `PrimeISPC/solution_1` is the wheel entry.
- `PrimeISPC/solution_2` is the new base-algorithm entry.

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
- `ispc-dev/RULES-REVIEW-2026-10-09.md` has the full compliance check, a PR description draft
  and the remaining checklist. The user wants **one PR with both solutions**.
- Added to task 2: run the solution_2 arm64 build and self-test on Ampere. It's the one
  untested cell in the review.
- When you finalise targets in task 1, update solution_1's README portability paragraph to
  match.

## Disclosure (user decision)

AI assistance is **disclosed in full** and is part of the story: an evaluation-driven,
hill-climbing agentic engineering loop. See the updated PR draft in `RULES-REVIEW-2026-10-09.md`.

In task 3, add this section to **both** READMEs, just before "Run instructions". Adjust the
numbers once they are final:

```
## How this was built

This solution was developed by agentic engineering with Claude (Anthropic): a Claude.ai session
for design, prototyping and coordination, a Claude Code session for benchmarking on Azure
(AMD Zen 3 and Zen 5, Ampere arm64), and the author directing priorities and decisions. The
method was evaluation-driven hill-climbing: every change was self-tested (`PRIMES_TEST=1`),
then benchmarked in interleaved runs against the previous build and the leading solutions, and
kept only if it won. The full record, including regressions and dead ends, is on the
[`ispc-dev` branch of the author's fork](https://github.com/cauldnz/Primes/tree/ispc-dev/ispc-dev).
```

Keep `ispc-dev` **public and unsquashed**: it is the evidence trail the PR links to.

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
