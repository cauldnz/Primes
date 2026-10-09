# Harness backlog

Improvements to the hill-climbing machine itself, ranked. Each run spends its first 30 to 40
minutes on the top open item (see `RUN-PLAN.md`), and its retrospective (`results/hc/RETRO.md`)
adds at most three new items. Background: `REVIEW-2026-10-10.md`.

| # | Item | Why | Status |
|---|---|---|---|
| 1 | Standing phase profile: a diagnostic build of each entry (never merged) with TSC or `clock_gettime` timers per phase, run on Zen 3 and Zen 5 for ours and the rival (the Zig wheel too) at the start of each run; results into "Where the cycles go" in `STATUS.md` | 3 of 11 predictions landed last run; none had a fresh profile | wheel done 2026-10-10 (`hc/diag-wheel-phases`, `hc/diag-zig-wheel-phases`); base still open |
| 2 | danielspaangberg's best faithful wheel (`PrimeC/solution_2`) as a wheel rival in `hc-pool.sh`, next to C5 | C5 is `algorithm=other`; the wheel category's leader was never measured | done 2026-10-10 (`ctrl2` in wheel runs: 5760of30030 owrb at 1T, epar at all threads) |
| 3 | Two-stage screen: three rounds, 1T and all threads, Zen 5 only; the full protocol only for candidates within 1% of a win | decisions take 30–40 minutes; most losers show by round 2 | open |
| 4 | Several candidates per task against one champion | shares the champion and A/A runs | open |
| 5 | Salvage rounds from a preempted task automatically (`tools/salvage.py`, by hand for now) | Spot took both Zen 5 nodes on 2026-10-09 | tool done; wire into `hc-pool.sh` |
| 6 | Intel AVX2 proxy size (for example `D16s_v3`) for the i7-9750H runner | no Intel core has run our code | waiting for Chris's OK |
| 7 | Prediction calibration column in the ledger, and a calibration line in each morning report | the machine's own score | open |
| 9 | Phase profiles of two builds must share a node (a `zig` task with `CTRL_REF` set to the ISPC diagnostic branch does it); `hc-pool.sh` should have a `profile` kind that runs any two diagnostic builds side by side | 2026-10-10: the first ISPC and Zig profiles ran on different nodes, so node-to-node spread mixed with the per-phase gap | workaround in use |
| 8 | Dashboard state sync when Chris's decisions merge experiments | seven merged experiments read "queued" until 2026-10-10 | done once by hand |
| 10 | Heartbeat and inbox inside the wait: every wait goes through `tools/wait.sh`, which publishes spend, background runs and a timestamp every 5 minutes, starts the cost meter if pools exist without it, and returns early with Chris's message when `INBOX.md` changes | 2026-10-10: Chris saw the page go stale and the spend stay at NZ$0 for most of each run, and his chat messages waited until the run's turn ended. The meter flushed every 15 minutes and only when started by hand | done 2026-10-10 (Claude.ai session): `tools/wait.sh`, `INBOX.md`, meter flush every 5 minutes, page shows inbox pick-ups. First live test is the next run |
