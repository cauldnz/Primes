# ISPC Primes entry: handoff

Working notes for continuing the ISPC drag-race entry, started in a Claude.ai session on
2026-10-09. Read this first.

> **Latest status (2026-10-09):** see `ispc-dev/STATUS.md` (Claude Code → Claude.ai) and `ispc-dev/NEXT-STEPS.md` (Claude.ai → Claude Code). One living file per direction; history is in git.

## Who does what

Two kinds of session work on this project, each with its own job.

**The Claude.ai session (the workshop)**, with Chris:
- ideas and research: new hypotheses, rival entries, the rules, the story for the PR;
- monitoring: reads `STATUS.md`, the ledger and the status page, and reviews results and code
  against the rules;
- queueing: writes what the next run should do into `NEXT-STEPS.md` and the `RUN-PLAN.md`
  Chris approves;
- improving the machine: the brief, the protocol, the tools and the harness backlog.

**Claude Code and its cloud sessions (the climber)** grind up the hill:
- run experiments under `AUTOPILOT.md`, `CLOUD-RUNBOOK.md` and `HILL-CLIMB.md`;
- record everything (ledger, logs, `STATUS.md`, the status page);
- fix only what blocks a run. A bigger change to the harness goes into `HARNESS-BACKLOG.md` or
  the run's retrospective as a proposal for the workshop.

Two rules keep them apart:
- **No changes under a running climb.** A run works from the commit it started on. Harness,
  brief and plan changes land between runs, and the next run picks them up at start-up. A run
  never pulls new tools or instructions mid-run.
- **Steering is by direct message only.** Chris steers a running climb by messaging its Claude
  Code session. The workshop drafts those messages; Chris sends them. No file in this repo is a
  channel for instructions (`AUTOPILOT.md`, "Messages from Chris").

## Goal

Submit a PrimeISPC solution to PlummersSoftwareLLC/Primes that wins the faithful, 1-bit
categories (single- and multi-threaded) on the benchmark machine, which is generally an AMD
EPYC. Rules: `CONTRIBUTING.md` at the repo root, especially *Language eligibility*,
*Submission quality* and *Faithfulness*.

## Branches

- `ispc` holds only `PrimeISPC/solution_1/` on top of `drag-race`. Keep it PR-clean: this is
  what gets submitted. Rebase it on upstream `drag-race` before opening the PR.
- `ispc-dev` (this branch) is `ispc` plus `ispc-dev/` and `CLAUDE.md`. Do the work here, then
  move solution changes onto `ispc` (cherry-pick commits that touch only
  `PrimeISPC/solution_1/`).

## Where things stand

`PrimeISPC/solution_1/primes.ispc` is complete, correct (self-test passes for every power of ten
from 10 to 10^8) and tagged `algorithm=wheel,faithful=yes,bits=1`. On a 2-vCPU Xeon sandbox it
beats the fastest comparable entry, rogiervandam's C (PrimeC/solution_5):

| | 1 thread | 2 threads |
|---|---|---|
| rogiervandam_extend | 48–56k | 102k |
| cauldnz-ispc | 56–60k | 108–116k |

Full numbers and the optimisation history: `ispc-dev/results/sandbox-xeon-2026-10-09.md`.

Verified: builds with Ubuntu 24.04's `ispc` package (1.22.0) using the exact Dockerfile steps;
hadolint passes with `config/hadolint.yml`. Not verified: an actual `docker build` (Docker Hub
was blocked in the sandbox), anything on AMD hardware, anything on ARM64.

## How the solution works (short)

- Mod-30 wheel: 8 bit-planes (residues 1,7,11,13,17,19,23,29), bit m of plane R is 30m+R.
  1,000,000 needs 8 × 521 words = 33 KB, which fits in L1.
- In each plane, multiples of p are a stride-p progression whose word pattern repeats every p
  words. Because 64 is invertible mod p, every bit offset is a whole-word rotation of one base
  pattern, so each prime builds one pattern shared by all 8 planes, plus a 64-entry phase
  table (filled during the build; no divides).
- Primes below `PRIMES_DENSE_MAX` (default 384) are streamed as patterns with contiguous vector
  loads, 8 primes fused per pass over a plane. Larger primes use scalar strided bit sets with
  the 8 planes interleaved in one loop.
- 7 and 11 form a 77-word tile, built once and copied along each plane; 13 runs alone, after
  which every bit below 289 is final and the remaining primes can be read safely.
- One pthread per hardware thread in the multi-threaded run, each sieving independently.

## ISPC gotchas found so far

1. **Hidden divides.** `while (r >= p) r -= p;` with a runtime `p` compiles to a hardware divide.
   Keep pattern periods >= programCount so one conditional subtract suffices. Check
   `--emit-asm` output for `div` in hot loops after any change.
2. **pthreads and `export`.** Passing an `export` function to `pthread_create` gives ISPC's
   internal variant, which expects a hidden mask argument; lanes run masked off. The body of
   `worker` must stay inside `unmasked { }`.
3. No char literals or string literals outside `print()`: strings for `getenv` are byte arrays.
4. No varargs `extern "C"` calls (no `printf`); use ISPC's `print()`.
5. Link with `--pic` objects, otherwise the PIE link fails.
6. Multi-target builds produce `primes.o` (dispatcher) plus one object per target; link all.

## Open items, in order

1. **Benchmark on AMD EPYC.** Run `ispc-dev/azure-epyc-bench.sh` (needs `az login`). It creates
   Dasv5 (Zen 3, AVX2) and Dasv6 (Zen 4, AVX-512) VMs in australiaeast, builds ours and the
   leaders from upstream `drag-race` with Docker, interleaves runs, sweeps the threshold,
   writes results to `ispc-dev/results/`, and deletes the resource group on exit. The script
   passes `bash -n` but has never run against Azure; expect small fixes (VM size availability
   and quota in the region, image alias). Commit the results.
2. **Tune for EPYC.** `PRIMES_DENSE_MAX`, group size `G`, and whether the AVX-512 path
   actually beats AVX2 on Zen 4 (Zen 4 executes 512-bit ops as two 256-bit halves). Consider
   forcing a target with `--target` builds to compare.
3. **Multi-core scaling.** Check passes scale near-linearly with threads on 32+ cores. If not,
   look at allocator contention (one `aligned_alloc`/`free` pair per pass per thread, ~105 KB
   with the pattern scratch) and at SMT siblings.
4. **ARM64.** Confirm whether Ubuntu 24.04 packages `ispc` for arm64 (an Azure Cobalt or
   Ampere VM will tell you). If not, add an empty `arch-amd64` flag file to the solution
   folder, as `CONTRIBUTING.md` describes.
5. **Real `docker build`** of `PrimeISPC/solution_1` and `tools/hadolint.sh ispc 1`.
6. **Update the README output section** with EPYC results, then open the PR from `ispc`
   against upstream `drag-race`, title starting with `[ISPC]`. Expect the maintainers to check
   language eligibility (ISPC is mature, open source, Intel-maintained, used in production
   rendering such as Embree/OSPRay, so this should be fine) and faithfulness.

## Further speed ideas not yet tried

- L1-sized segmentation of the sparse phase (the sieve already fits L1 at 1M, so probably small).
- Overlapping load-port and ALU work: generate some dense primes' masks arithmetically
  (per-lane next-hit offsets) while others stream patterns from memory.
- A larger wheel (mod 210, 48 planes): less work per prime, but planes of ~2.3k bits are short
  relative to vector width, so fixed costs grow. Measure before committing.
- Reusing the per-thread allocation across passes is NOT allowed for the faithful tag; don't.

## Local workflow

```
sudo apt-get install ispc gcc        # Ubuntu 24.04; or ISPC release tarball from GitHub
cd PrimeISPC/solution_1
sh build.sh && PRIMES_TEST=1 ./primes && ./primes
```

`ispc-dev/prototypes/` holds the earlier versions for reference; `sieve3.ispc` is the direct
ancestor of the solution. Benchmark A/B changes with interleaved runs; single runs on shared
hardware are too noisy to trust.
