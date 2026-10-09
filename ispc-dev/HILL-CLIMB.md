# Hill-climbing protocol for the ISPC entries

Until now the search has run by hand: an idea here, a benchmark there, results passed between two
sessions. Claude Code now has a working harness, with Azure VMs, Batch Spot pools, a self-test and
interleaved runs, so it can run the loop itself. This file sets the rules for that loop. The
Claude.ai session reviews the ledger and the backlog; it no longer relays individual experiments.

## The loop

1. **Pick** the top hypothesis from the backlog below. Write down the prediction first: which
   number moves, on which machine, by roughly how much, and why.
2. **Plan** the smallest change that tests it. Change one thing at a time. A parameter sweep
   counts as one experiment.
3. **Implement** on a branch named `hc/<id>-<slug>` off `ispc-dev`.
4. **Gate** before any timing:
   - `PRIMES_TEST=1` passes on the build that will be measured.
   - The change keeps the entry within its rules (see "Rules gate").
5. **Evaluate** with the protocol below.
6. **Decide** with the acceptance rule. Merge winners into `ispc-dev`, then write the ledger
   entry either way. Losers and dead ends are results too: they stop the next session repeating
   the experiment.
7. **Update the backlog**: re-rank it and add any hypothesis the result suggests.

## Evaluation protocol

- Controls in every round. Each round runs the current champion build and rogiervandam's
  `PrimeC/solution_5` next to the candidate, on the same VM, interleaved. Compare the candidate
  with the champion from the same round, never with a number from an earlier run. Today's Zen 5
  results show why: the same build measured 150k at 13:49 and 126k at 14:45, while C5 held at
  139k both times.
- Rounds. At least five interleaved rounds per machine. Report the median and the range.
- Machines. Every decision needs Zen 3 (`D16as_v5`, AVX2 only) and Zen 5 (`D16as_v7`). Add
  Zen 4 (`D16as_v6`) and arm64 (`D4ps_v6`) for any change to build targets or shared code.
- Metrics. Passes at 1 thread, and at all threads. Record half and quarter too; the official
  runners report them.
- Raw logs go under `ispc-dev/results/hc/<id>/`. Commit them even when the experiment fails.

## Acceptance rule

Keep a change only if all of these hold:

- the median improves by at least 2% on both Zen 3 and Zen 5, at 1 thread or at all threads;
- every candidate round beats the champion in its own round on at least one of those machines,
  so noise alone can't account for the gain;
- no machine or thread count regresses by more than 1%;
- the code stays readable enough to explain in the README.

When a result falls between 0 and 2%, rerun it with ten rounds before deciding.

## Rules gate

Check this before timing, and again before merging:

- Faithful (both): all state is in `struct Sieve`; a new instance is allocated every pass;
  nothing persists between passes; no external dependency does the sieving.
- Base (solution_2): one operation per composite in the source; next-prime search over odd
  numbers from 3; no prime knowledge beyond 2 being even; no page segmentation.
- Wheel (solution_1): tags stay `algorithm=wheel`. If a change moves the design towards
  something a reviewer would call "other", stop and flag it.
- Read `ispc-dev/RULES-REVIEW-2026-10-09.md` when unsure.

## Ledger

Append one row per experiment to `ispc-dev/results/hc/LEDGER.md`:

| id | date | entry | hypothesis | prediction | Zen 3 1T/16T (median, Δ) | Zen 5 1T/16T (median, Δ) | verdict | commit |
|---|---|---|---|---|---|---|---|---|

Then add a short note per experiment under the table: what happened, and what it suggests next.

## Budget and stop conditions

- Azure credit. About NZ$248 remains on the Visual Studio subscription. Prefer Batch Spot.
  Stop and ask Chris before spending more than NZ$50 in one session.
- Diminishing returns. Stop a line of attack after three experiments in a row on it fail the
  acceptance rule.
- Time box. Submission-readiness comes first (NEXT-STEPS tasks 3 and 4). Hill climbing runs
  after the PR is opened, or in parallel only if it doesn't block the PR.
- No pushes to `ispc` and no PR changes without Chris's explicit OK. Winners reach the PR
  through a follow-up commit he approves.

## Backlog (ranked)

Seeded from today's results. Re-rank after each experiment.

### Wheel (solution_1)

1. **Zen 5 drift.** First explain the 150k to 126k change on `D16as_v7`. Candidates:
   - different host CPU stepping or clocks;
   - noisy neighbours;
   - a build difference between the two runs.

   Run the 13:49 build and today's build in the same round. Until this is explained, Zen 5
   numbers can't support decisions.
2. **Gang width on arm64.** `neon-i32x8` beat `neon-i32x4` by 15% on Cobalt 100 (63.2k against
   54.9k, three rounds). Make it the arm64 default, then confirm on Neoverse-N1.
3. **Fusion group size `G`** (now 8) against gang width. Wider gangs change the balance between
   loads in flight and pattern registers. Sweep G over 4, 6, 8, 12 with avx2-i32x16 and
   avx512skx-x16.
4. **Dense threshold with the new gangs.** 256 was tuned on avx2-i32x8. Re-sweep 192–384.
5. **Pattern scratch size.** `Group` holds about 70KB, which spills a 32KB L1 on Zen 3 and Zen 4.
   Size the buffers to the largest dense prime actually used (now 256, not 1,024).
6. **Sparse phase.** Large primes take roughly a third of the cycles. Try unrolling the
   eight-plane loop by two, and processing two primes per loop.
7. **Mod-210 wheel** (48 planes). It does less work per prime but has shorter planes. Prototype
   it on the sandbox first, because it's a large change.

### Base (solution_2)

1. **Baseline it properly** against mike-barber's Rust and GordonBGood's Chapel on Zen 3 and
   Zen 5. The Rust run failed in the 14:45 round.
2. **Dense limit** with the AVX2 path on Zen: 128 against 192 and 256.
3. **Byte against 64-bit word addressing** for the sparse phase.
4. **Block the dense phase** in L1-sized chunks, the "striped-blocks" idea from the Rust entry.
   Check against the base rules: each composite must still get its own operation.

## Writing

Anything committed to `PrimeISPC/`, the PR, or this branch's notes follows Chris's house style:
the `house-style` and `economist-style` skills in `~/.agents/skills/` on his machine. Load both
before writing a README, a PR description or a ledger note. Commit messages count too.
