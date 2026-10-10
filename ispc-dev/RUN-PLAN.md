# Run plan: the L2 wall (agreed with Chris, 2026-10-11 06:30)

Read this after `AUTOPILOT.md`. It sets this run's priorities, time box and end-of-run steps.
Everything else in the brief, the runbook and `HILL-CLIMB.md` still applies, including the
"Never without Chris" list. The previous plan is in git history; its results are in the morning
report of run ap-20261010T0715Z in `STATUS.md`.

## Limits

- Time box: 4 hours from the session start. Stop starting experiments at 3h15, so the final
  scoreboard and shutdown fit in the last 45 minutes.
- Azure: NZ$30 for the run, no new pools past NZ$25, Spot only, 128 Spot vCPUs in all. At most 6
  pools. Every pool's deadline is the run's end; take a pool down as soon as its work is done.
- The Azure secret from 10 October may have expired. If the start-up login fails, stop and tell
  Chris in the session (he rotates it); don't fall back to local mode for this run, because
  every priority needs the deciding machines.

## Chris's decision on the rules questions (2026-10-11)

Build and measure F1 (alternating sweep direction) and F2 (blocking) for the base, though both
are grey under the base rules, and remove them later if the maintainers say no. IDEAS item 10
is unblocked for this run in that form. To keep that reversible:

- **Grey work lives on its own lineage, `hc/champion-grey`**, branched from `hc/champion`.
  Grey candidates branch off it and are measured against `hc/champion` (the clean champion), so
  every grey number is a gain over what we'd submit today. Keeps merge into `hc/champion-grey`
  only. `hc/champion` stays rules-clean and PR-ready.
- In-rules work (the wheel's F1, F4, F5, F6) branches off `hc/champion` as usual. If one is
  kept, merge it into `hc/champion` and then into `hc/champion-grey`, so the grey line carries
  every clean keep.
- Don't change any solution's tags. A grey branch gets a `RULES.md` at the solution root saying,
  in two or three sentences, which rule text it stretches and how.

## State at the start

- `hc/champion` = `37e19c7`. Two keeps wait on Chris in the kickoff message: the thread-count
  fix (`hc/idea1-affinity`, `8fd7f1f`) and `hc/wheel-group32` (`5a68114`). If he approves them,
  fast-forward or merge them into `hc/champion` before branching anything, and record the merge.
- Base vs Rust (thread-count build): Zen 5 +0.9% 1T / +14.4% all; Zen 3 +6.9% / +4.9%; Zen 4
  +8.3% / +8.0%; Cobalt 100 −2.1% / −1.9%; Zen 5 96 vCPU +3.1% / +10.9%.
- The diagnosis (IDEAS.md, Fable pass): the 62.5 KB base sieve doesn't fit Zen 5's 48 KB L1D and
  every phase sweeps it top to bottom, so each sweep is an L2 fill plus writeback; under SMT two
  sieves share one L2 port and the sparse phase loses 9%. Everyone in the base category is at
  this wall, Rust included.

## Priorities, in order

1. **F1, base: alternate the sweep direction per factor** (`hc/f1-alternate`, off
   `hc/champion-grey`). Factor k sweeps up, factor k+1 down, in both the dense and the sparse
   loops; each still clears every composite individually, stepping 2 × factor. Prediction in
   IDEAS.md: +10% to +20% at 1T on Zen 5, more under SMT.
   - **Falsify first, cheaply:** a same-node phase profile, champion against candidate, on one
     Zen 5 node. If sparse cycles at 1T don't drop by at least 10%, the L1 story is wrong: record
     that, stop F1, and move to F2.
   - Otherwise evaluate as usual (Zen 5 and Zen 3 deciding, Zen 4 recheck, Cobalt 100 gate) at
     1T, one thread per core and all threads, then once on the 96-vCPU node at 48 and 96 threads.
2. **F2, base: blocking** (`hc/f2-block`, off `hc/champion-grey`). After the dense phase, sieve
   the sparse factors block by block: for each L1-sized block, every factor clears its
   composites in that block, stepping 2 × factor, carrying its next index to the following
   block. The outer loop (find next prime, clear its multiples) stays the same in result; only
   the nesting of the clearing changes. The precedent is rogiervandam's merged
   `PrimeC/solution_5/src/sieve_base.c` (`shakeSieve`, PR #995), tagged base and faithful; read
   it before writing. Block sizes 16, 24 and 32 KB as one sweep experiment. Prediction: +30% or
   more at 1T on Zen 5, more under SMT. Same machines and thread counts as F1.
   - If both F1 and F2 are kept, measure F1 on top of F2 once; expect little (blocking makes the
     direction mostly irrelevant).
3. **F1, wheel** (in-rules; off `hc/champion`): alternate per group pass and per sparse prime.
   Expect about 0 at 1T, +3% to +6% at all threads. Judge it at all threads on the 32-vCPU and
   96-vCPU nodes, under the usual rule.
4. **In-rules leftovers from IDEAS.md**, while nodes are free: F4 (`PRIMES_DENSE_MAX` 384, 512,
   640; no build), F5 (`--addressing=64` on the base's dense loop; the x16 fold as an agent task),
   F6 (AVX-512 off at 96 threads on the 96-vCPU node).
5. **IDEAS 12 (tile13) on a quiet Zen 5 node**, 12 rounds: it was positive on every machine and
   failed only on Zen 5's noisy intervals.

Background agents (two at most) write F2 and the F5 fold while Batch runs F1's profile.

## The numbers Chris needs for the upstream issue

For F1 and F2 each, in the morning report, before anything else:
- the gain over the clean champion and over mike-barber's Rust, Zen 5 and Zen 3, at 1T, one
  thread per core and all threads, with intervals; and the 96-vCPU numbers;
- the phase-profile evidence (sparse and dense cycles, champion against candidate);
- a plain description of the change in the rules' own words: what the outer loop does, how each
  composite is cleared, how the step works. Three sentences, no claims about whether it's legal.

## Morning report additions

Besides the usual report (section 9 of `AUTOPILOT.md`):
- **Decisions and why**, from the `st.py decide` records.
- Both lineages: what's on `hc/champion` (clean) and on `hc/champion-grey`, each against Rust on
  every machine measured.
- The overhead split and the busy share of node time (target 60%; last run 69%).
