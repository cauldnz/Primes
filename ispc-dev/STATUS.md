# Status from the Claude Code session

Autopilot lock: ap-20261009T0607Z 2026-10-09T06:07Z

**Last updated:** 2026-10-09 15:35 AEST. Living file; earlier versions are in
`git log -p ispc-dev/STATUS.md`. Replies go in `ispc-dev/NEXT-STEPS.md`.

## Autopilot hourly review

**18:05 AEST (hour 2).**
- Worked: hc-002 confirmed on fresh nodes (+22% to +24% at 1T on Zen 3 and Zen 5) and merged; hc-004 (wheel, lone prime 13) gained 4.9% to 8.7% and merged.
- Didn't: hc-005 (wheel unmasked stores) lost 1.7% on Zen 5; hc-006 hit a noisy Zen 3 node (control swung 36k–59k) and is being rerun.
- Protocol: one slip caught and fixed. A run started 17 seconds after a merge would have compared against the wrong champion; I stopped it before any round, and runs now pin `BASE` to a commit.
- Spend: NZ$1.10. The four-pool limit binds, not money.
- Next: finish hc-006b, hc-007 and hc-008 (wheel), then hc-009 (base scan) and a Zen 5 re-profile of the base champion. About two hours before the stop, a final scoreboard run of both champions against their rivals.

**17:05 AEST (hour 1).**
- Worked: the profile (hc-001) pinned 60–70% of the base gap on the dense phase; hc-002 (vector dense) gained 23% at 1T and hc-003 (sparse pointer walk) 12% on Zen 5.
- Didn't: a higher dense limit with vector resets; ISPC compile time explodes past factor 128 (over 7 minutes for one target), so it's parked.
- Protocol: followed, with one gap: `D16as_v5` gave Zen 4 twice, so hc-002 and hc-003 have no Zen 3 data. `D16a_v4` gives a 7763 and is now the Zen 3 size.
- Spend: NZ$0.54 so far.
- Next: confirm hc-002 on fresh nodes (gain above 20%), then the wheel (hc-005 running, hc-004 queued). That's the best use of the time: wheel is objective 2 and base has closed most of its gap.

## Where the cycles go (hc-001, 16:15–16:28 AEST)

Measured on Batch Spot nodes at 1T. Raw output in `results/hc/001-profile/`.

- Machines. `D16as_v5` came up as an EPYC 9V74 (Zen 4) with AVX-512 hidden, not the usual
  7763 (Zen 3). `D16as_v7` was an EPYC 9V45 (Zen 5). The v5 size no longer pins Zen 3.
- Counters. Neither size exposes hardware PMU counters: `cycles`, `instructions`, branch and
  L1 events all read "not supported". perf fell back to `cpu-clock` sampling. For the phase
  split I used TSC timers built into copies of our base entry and the Rust entry
  (`prototypes/profile/`); three rounds agreed within 0.1% on both machines.

Base entry against mike-barber's Rust, cycles per pass (TSC at 2.6GHz):

| phase | Zen 4 ours | Zen 4 Rust | Zen 5 ours | Zen 5 Rust |
|---|---|---|---|---|
| dense (factors < 128) | 114k (42%) | 79k (36%) | 69k (44%) | 40k (37%) |
| sparse | 143k (53%) | 135k (62%) | 79k (51%) | 64k (59%) |
| next-prime scan | 5k (2%) | 6k (3%) | 4k (2%) | 4k (4%) |
| set-up and allocation | 2k (1%) | n/a | 1k (1%) | n/a |
| total | 270k | 219k | 157k | 108k |

- The gap is 51k cycles a pass on Zen 4 and 49k on Zen 5. Dense accounts for 35k and 29k of it,
  sparse for 8k and 15k. The scan and set-up don't matter.
- Rust's dense phase costs a flat 2.7k cycles per factor, whatever the factor. Its macro writes
  a load, the single-bit ORs and a store for every word of a chunk, in order, and LLVM's SLP
  vectoriser turns that into AVX2 ORs with constant masks. ISPC's pipeline doesn't run SLP, so
  ours stays scalar: 4.5k to 5.6k cycles per factor below 70 on the local Xeon.
- Wheel (perf `cpu-clock`, Zen 5): the fused pattern groups (`apply_group`) take 46%, the
  sparse loop inlined in `run_sieve` 42%, the 7·11 tile (`dense_primes`) 12%. Zen 4 is the same
  shape: 43%, 41%, 12%.
- C5 ships stripped binaries, so perf shows addresses only; its hottest address takes 5.7%. The
  Rust profile under perf is unreliable (the chrooted run used 0.1 CPUs); the TSC build stands.
- Backlog consequence: dense vectorisation first (hc-002), then the sparse loop on Zen 5, then
  a higher dense limit once dense resets are cheap.

## Changes since last update

**Autopilot run ap-20261009T0607Z (16:07 AEST onwards, in progress).** Details per experiment
are in `results/hc/LEDGER.md`; the page at https://cauldnz.github.io/Primes/ has the live state.

- Base entry: +22% to +24% at 1T from vector dense resets (hc-002), then +12% on Zen 5 from a
  pointer-walk sparse loop (hc-003). Both are on `hc/champion` (`4d35020`). The base entry now
  beats mike-barber's Rust at 1T on Zen 3 (57.2k against 55.4k) and Zen 4.
- Wheel: hc-005 (unmasked stores) gained 4% on Zen 3 but lost 1.7% on Zen 5, so it was
  rejected; an AVX2-only version (hc-007) is queued. hc-004, hc-006 and hc-008 are running or
  queued.
- `D16as_v5` now lands on Zen 4 (EPYC 9V74, AVX-512 hidden). `D16a_v4` gives a Zen 3 (7763).

Earlier entries:

- NEXT-STEPS tasks 1 and 2 are done. The tables are below and the raw logs are in
  `results/azure-202610091445/`. Machines: Zen 3, Zen 4, Zen 5, Ampere Altra and Cobalt 100,
  all on Batch Spot.
- Target decision for x86: keep `sse4-i32x8,avx2-i32x16,avx512skx-x16`.
- Target decision for arm64: switch the default to `neon-i32x8`. It gains 4% on Neoverse-N1 and 15% on Cobalt 100.
- HILL-CLIMB backlog item 1 (the Zen 5 drift) is explained. The code didn't regress: the old and
  new builds measured within 1% of each other in the same round, on two separate Zen 5 nodes.
  The drift comes from the machine, and C5 drifts too.
- solution_2 builds and passes its self-test (13 of 13) on arm64, on both Ampere and Cobalt 100.
  This closes the open cell in `RULES-REVIEW.md`.
- A correction to `HILL-CLIMB.md` base item 1: the Rust run did not fail. All three rounds are
  in the 14:45 logs (they were still partial when you read them).
- Times here are now AEST, as you asked.

## Wheel target matrix (NEXT-STEPS task 1)

Passes in 5 s, 16-vCPU Batch Spot nodes (8 cores plus SMT), three interleaved rounds per
machine, median shown. Zen 3 and Zen 4 rounds sat within 1% of each other. On Zen 5, round 1
ran about 16% slow for every wheel variant while C5 and the base entry held steady, so the
median discards it.

| 1T / 16T | Zen 3 (EPYC 7763) | Zen 4 (EPYC 9V74) | Zen 5 (EPYC 9V45) |
|---|---|---|---|
| `avx2-i32x8` (old default) | 72.2k / 612k | 84.2k / 721k | 126.2k / 975k |
| `avx2-i32x16` | 81.5k / 705k | 97.4k / 834k | 147.0k / 1.17M |
| `avx512skx-x8` | n/a | 92.0k / 749k | 138.2k / 1.05M |
| `avx512skx-x16` | n/a | 99.8k / 841k | 150.9k / 1.25M |
| default (dispatch) | 80.2k / 704k | 99.0k / 841k | 139.8k / 1.24M |
| C5 (rogiervandam) | 65.2k / 532k | 97.0k / 770k | 139.8k / 1.20M |

- Gang width. `avx2-i32x16` beats `avx2-i32x8` on every machine, at both thread counts:
  - Zen 3: 13% at 1T, 15% at 16T
  - Zen 4: 16% at 1T, 16% at 16T
  - Zen 5: 17% at 1T, 20% at 16T

  The README figures of 11% (Zen 3) and 14% (Zen 5) understate the gain; use these numbers.
- AVX-512 stays. `avx512skx-x16` beats `avx2-i32x16` by 2% at 1T on Zen 4 and Zen 5, and at
  16T by 1% on Zen 4 and 6% on Zen 5.
- Runner 74 risk (AVX2 only, unknown host). With `avx2-i32x16`, the wheel now beats C5 at 1T on
  all three Zen generations: by 25%, 0.4% and 5%. At 16T it leads by 32% on Zen 3 and 8% on
  Zen 4, and trails by 2% on Zen 5. It trailed by 18% with `avx2-i32x8`.
- Dense threshold, re-swept with the new defaults (one run each, 1T / 16T):

  | `PRIMES_DENSE_MAX` | Zen 3 | Zen 4 | Zen 5 |
  |---|---|---|---|
  | 192 | 81.3k / 691k | 99.0k / 817k | 146.8k / 1.24M |
  | 256 | 78.5k / 704k | 97.8k / 833k | 149.6k / 1.24M |
  | 320 | 76.4k / 667k | 93.2k / 812k | 141.5k / 1.15M |

  192 ties 256 at 1T and loses at 16T, so 256 stays.

### arm64 (4 vCPU), three rounds, median

| 1T / 4T | Ampere Altra (Neoverse-N1) | Cobalt 100 (Neoverse-N2) |
|---|---|---|
| wheel `neon-i32x4` (current default) | 39.1k / 156k | 54.9k / 219k |
| wheel `neon-i32x8` | 40.8k / 163k | 63.2k / 253k |

I'll commit the `neon-i32x8` default for arm64 to `ispc-dev` next. The self-tests already pass
on both machines with that build.

## Base entry (NEXT-STEPS task 2)

Three rounds, median, 1T / all threads.

| | Zen 3 | Zen 4 | Zen 5 | Ampere (4T) | Cobalt 100 (4T) |
|---|---|---|---|---|---|
| `cauldnz-ispc-base` | 44.7k / 341k | 63.7k / 497k | 87.5k / 690k | 35.2k / 139k | 41.0k / 163k |
| mike-barber Rust extreme-hybrid | 52.4k / 411k | 76.6k / 608k | 126.6k / 877k | 36.8k / 147k | 42.9k / 171k |
| GordonBGood Chapel extreme_hybrid (4T) | 47.4k / 192k | 68.5k / 282k | 114.4k / 438k | n/a | n/a |

- The AVX-512 penalty doesn't hold on AMD. Builds with and without `avx512skx-x16` measured
  identical on Zen 4 (63.7k both) and Zen 5 (87.5k both). The 18% sandbox penalty looks like an
  Intel effect; excluding AVX-512 does no harm, so I'd keep the default as it is.
- Gap to Rust at 1T: 15% on Zen 3, 17% on Zen 4, 31% on Zen 5, and 4% to 5% on arm64. The gap
  widens on Zen 5, which suggests the Rust code uses Zen 5's wider core better. I haven't tested
  that.

## Zen 5 drift (HILL-CLIMB backlog item 1)

Same-round A/B on two separate D16as_v7 Spot nodes: old = `83c20ec`, new = the 15:00 working
tree, which includes `0b702ef` and `0a4e409`. Three rounds, median.

| 1T / 16T | node A | node B |
|---|---|---|
| new (default targets) | 147.2k / 1.23M | 143.5k / 1.21M |
| old (`83c20ec`) | 147.6k / 1.23M | 142.5k / 1.22M |
| new, forced `avx2-i32x8` | 127.9k / 970k | 121.0k / 969k |
| C5 | 133.4k / 1.25M | 130.7k / 1.15M |

- Old and new agree within 1% on both nodes, so there's no regression.
- Node B ran about 3% slower than node A, for every build.
- C5 itself measured 139.8k in the matrix run and 133.4k and 130.7k here. Cross-run comparisons
  are therefore meaningless on Zen 5; only same-round ratios count. That matches the
  `HILL-CLIMB.md` evaluation rule.
- Open question: what is the first-round slow mode? It hit only the wheel builds, only once, on
  one node. That matters for the leaderboard, because the official runners make one run.
  Hypothesis: the per-pass `aligned_alloc`/`free` of about 105KB interacting with page faults or
  transparent huge pages (C5 uses mimalloc). I'd add this to the HILL-CLIMB backlog.

## Proposed additions to the HILL-CLIMB evaluation protocol

All four target noise sources we saw today:

1. Discard one warm-up round before the scored rounds.
2. Randomise the order of builds within each round.
3. Run an A/A pair, the champion built twice under two tags, so each run measures its own noise floor.
4. Add `ispc-dev/analyze.py`, which parses the logs and reports the median, the range,
   per-round ratios to the champion and to C5, and a keep / revert / rerun verdict under the
   acceptance rule.

## Capabilities

- **Azure Batch Spot, the default for benchmarks.**
  - Command: `MODE=batch SUITE=default|targets ./azure-epyc-bench.sh <size...>`.
  - Account `batchllmwestus2gves` has 128 Spot vCPUs.
  - Nodes allocate in about 40 s and tasks start about 90 s after submission.
  - Sizes proven to work:
    - D16as_v5 (Zen 3), D16as_v6 (Zen 4), D16as_v7 (Zen 5)
    - D4ps_v5 (Ampere), D4ps_v6 (Cobalt 100)
  - Batch also lists D32–D96 as v5, v6 and v7, all untested.
  - Cost guards:
    - Each pool's autoscale formula drops to 0 nodes after `MAX_MINUTES`, even if the script dies.
    - The job terminates when its task completes, and the task has a wall-clock limit.
    - The pool, job and uploaded blob are deleted on exit.
- **Plain VMs** (`MODE=vm`), regular priority only, since this subscription offer can't use
  Spot VMs. 20 vCPU per region.
- **Local Podman** (AVX2): free builds and self-tests. Timings are noise.
- **Git:** a standing OK to push results to `ispc-dev`. The `ispc` branch and the PR need Chris's OK.
- About NZ$248 of Azure credit remains. Today's runs cost a few dollars.

## Gotchas

- Build PrimeC/solution_5 with BuildKit. The legacy builder makes it compile nothing and still
  exit 0.
- Windows checkouts are CRLF; the script ships LF copies.
- Run the bench script from a copy. Bash reads scripts as it goes, so editing one mid-run can
  break it.
- `az batch task file download` won't overwrite an existing file. The script downloads to a temp
  file and moves it.
- With `BASE=HEAD`, "old" equals "new" once a change is committed. Set `BASE` to the commit before
  the change.

## Next

1. Commit the `neon-i32x8` arm64 default and push.
2. NEXT-STEPS task 3: the README Output sections and portability paragraph, using the numbers
   above. Do you want five-round medians first? The protocol asks for five; this matrix has three.
3. Chris has asked for a Claude Code cloud session to run HILL-CLIMB unattended for a few hours.
   I'm setting that up with him now. Expect a `ispc-dev/CLOUD-RUNBOOK.md`.
