# Harness backlog

Improvements to the hill-climbing machine itself, ranked. Each run spends its first 30 to 40
minutes on the top open item (see `RUN-PLAN.md`), and its retrospective (`results/hc/RETRO.md`)
adds at most three new items. Background: `REVIEW-2026-10-10.md`.

| # | Item | Why | Status |
|---|---|---|---|
| 1 | Standing phase profile: a diagnostic build of each entry (never merged) with TSC or `clock_gettime` timers per phase, run on Zen 3 and Zen 5 for ours and the rival (the Zig wheel too) at the start of each run; results into "Where the cycles go" in `STATUS.md` | 3 of 11 predictions landed last run; none had a fresh profile | open |
| 2 | danielspaangberg's best faithful wheel (`PrimeC/solution_2`) as a wheel rival in `hc-pool.sh`, next to C5 | C5 is `algorithm=other`; the wheel category's leader was never measured | open |
| 3 | Two-stage screen: three rounds, 1T and all threads, Zen 5 only; the full protocol only for candidates within 1% of a win | decisions take 30–40 minutes; most losers show by round 2 | open |
| 4 | Several candidates per task against one champion | shares the champion and A/A runs | open |
| 5 | Salvage rounds from a preempted task automatically (`tools/salvage.py`, by hand for now) | Spot took both Zen 5 nodes on 2026-10-09 | tool done; wire into `hc-pool.sh` |
| 6 | Intel AVX2 proxy size (for example `D16s_v3`) for the i7-9750H runner | no Intel core has run our code | waiting for Chris's OK |
| 7 | Prediction calibration column in the ledger, and a calibration line in each morning report | the machine's own score | open |
| 8 | Dashboard state sync when Chris's decisions merge experiments | seven merged experiments read "queued" until 2026-10-10 | done once by hand |
