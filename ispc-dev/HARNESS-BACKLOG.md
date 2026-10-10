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
| 10 | Heartbeat inside the wait: every wait goes through `tools/wait.sh`, which publishes spend, background runs and a timestamp every 5 minutes and starts the cost meter if pools exist without it | 2026-10-10: the page went stale and spend stayed at NZ$0 for most of each run; the meter flushed every 15 minutes and only when started by hand | done 2026-10-10. A file inbox for Chris (`INBOX.md`) was added and removed the same morning: anything that can push to `ispc-dev` could have steered a run that holds Azure credentials. Chris steers only by direct message |
| 11 | Short turns: a run ends its turn while Batch tasks run and wakes itself with `send_later` every 10 minutes; `hc-pool.sh collect` fetches the output of tasks whose watcher died in a container pause | Chris's chat messages only reach a session between turns, and runs were one long turn | done 2026-10-10 at Chris's direct request, between runs (`AUTOPILOT.md` "Short turns", `CLOUD-RUNBOOK.md` "Idle pause"); first live test is the next run |
| 12 | The page's Log follows the run: `tools/st.py current` and `st.py exp` add an event whenever the step or a verdict changes | the 2026-10-10 run wrote four log entries in 3.5 hours | done 2026-10-10 at Chris's direct request |
| 13 | The cost meter dies when the container pauses between short turns; restart it at every wake-up (`wait.sh 1` does, if called) and backfill from Batch task times. Better: compute node-minutes from Batch's own pool usage data, not a local sampler | 2026-10-10 leaderboard check: the meter recorded 18 of about 137 node-minutes; the rest were added to `cost-log.csv` as `batch-estimate` rows | open |
