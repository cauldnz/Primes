# Run plan: base first (agreed with Chris, 2026-10-10)

Read this after `AUTOPILOT.md`. It sets this run's priorities, time box and end-of-run steps.
Everything else in the brief, the runbook and `HILL-CLIMB.md` still applies, including the
"Never without Chris" list. Earlier plans are in git history.

Chris, 09:58: the next runs focus on the base entry. A high place on the base leaderboard, where
human experts have spent the most effort, is what shows the machine competing with them.

## Limits

- Time box: 4 hours from the session start. Stop starting experiments at 3h15, so the final
  scoreboard and shutdown fit in the last 45 minutes. If the Azure login fails mid-run (the
  secret expires), stop starting work, collect what you can and shut down cleanly.
- Azure: NZ$30 for the run, no new pools past NZ$25, Spot only. The account has 128 Spot vCPUs:
  at most 4 pools and 8 nodes, and never more than 128 vCPUs in all. Every pool's deadline is the
  run's end.
- Account names come from `BATCH_ACCOUNT` and `BATCH_RG`. If they aren't set in the environment,
  Chris gives them in the kickoff message; set them for the session and never write them to a
  file.

## How this run works (new since the last run)

- **Ticks** (`AUTOPILOT.md` 2a): short turns, each ending with a `send_later` wake-up, so Chris's
  messages get through. Results come back through blob storage: `hc-pool.sh submit`, then
  `tools/tick.sh` (collect, tally, publish) at the start of every tick. Never `hc-pool.sh run`,
  which blocks.
- **Background agents** (2b) for long local work: writing and gating candidates, profiling
  builds, the morning report.
- **Reasoning** (2c): `st.py decide` for every decision. The log flags verdicts without one.
- **Acceptance by confidence interval** (`HILL-CLIMB.md`): keep when the 95% interval of the
  per-round paired ratio clears +1% on both deciding machines; more rounds while it straddles;
  revert on a 1% regression or an interval that can't reach +1%. Start with six rounds.
- **Overhead**: report node-minutes split into boot and start task, builds, measuring and idle,
  per experiment and for the run (backlog item 17). Aim for measuring to be at least 60%.

**The first two ticks are the dry run** for the parts that haven't run before. Check, and record
each as an event:
1. a task submitted with `hc-pool.sh submit` shows up in `results/hc/jobs.tsv`, and `tick.sh`
   copies its partial output while it runs;
2. when it ends, `tick.sh` fetches the final output from blob storage and marks the job done;
3. `hc-pool.sh tally` adds node-minutes to `results/cost-log.csv` and spend moves on the page;
4. the `send_later` wake-up fires and the next tick carries on from git and Batch alone.

If submit, collect or tally fails and the fix takes more than 15 minutes, fall back to
`hc-pool.sh run` for the rest of the run, waiting with `tools/wait.sh` in steps of 10 minutes or
less, and say so in the event and the morning report. Ticks and `send_later` stay either way.

## State at the start

- `hc/champion` = `a1433d9` (wheel code `059b8f3`, with hc-045; base code unchanged since
  `4c7dc69`). Pin it; move the pin only when you merge a winner.
- The base entry against mike-barber's Rust, 1T / all threads (final3): Zen 3 +7% / +5%, Zen 4
  +8% / +8%, Zen 5 +2% / +16%, Cobalt 100 −4% / −4%.

## Priority 0, done: does our harness reproduce the leaderboard?

The leaderboard check of 10 October (`results/leaderboard-check-2026-10-10.md`) built the top
ten faithful 1-bit base entries on our nodes. What it changes for this run:
- **Zen 5 (`D16as_v7`) tracks the Threadripper for Rust and Nim within 2%**, so it stays the
  headline machine. Other entries run 9–20% slower here, so compare against Rust, not them.
- **Swift is the base entry to beat at 1T on the Threadripper** (122,869), 3% above our 119.8k on
  our Zen 5 if we track the Threadripper as Rust does. We can't reproduce Swift's speed (15%
  slower here), so treat its official number as the target.
- **Zen 3 is a poor stand-in for the official EPYC VM**: that VM runs Rust 17% faster than our
  Zen 3. The VM is AVX2-only, and `D16as_v5` gives a Zen 4 with AVX-512 hidden. Test it as the
  stand-in first (priority 1).
- The check ran three rounds; its medians are indicative.

## Priorities, in order

1. **Pick the second deciding machine.** One `board`-style task on `D16as_v5` with Rust and our
   base, six rounds, 1T. If Rust lands within 5% of the EPYC VM's 62.7k–63.1k, `D16as_v5`
   replaces `D16a_v4` as the second deciding machine for this run (record it with `st.py
   decide`); Zen 3 then runs only for regressions. Otherwise keep `D16a_v4`.
2. **Profile the base** (harness backlog item 1): phases for ours and Rust on one node each,
   Zen 5 and the second deciding machine, at 1T. Every later hypothesis names its phase and the
   share at stake.
3. **Zen 5 at one thread**: about +3% to pass Swift's official number, if the profile shows where.
4. **Arm**: close the 4% gap to Rust on Cobalt 100.
5. **The SSE4-only Celeron**: an SSE4-only build (`ISPC_TARGETS=sse4-i32x8`) against Rust's SSE4
   path, on the second deciding machine. No Intel sizes without Chris's OK (backlog item 6).
6. **Thread scaling**: all threads at 32 and 64 vCPUs on Zen 5, one large node at a time, inside
   the 128-vCPU quota. Look at per-pass allocation and SMT.
7. Only then the wheel: the Zig wheel's lead and the Rust wheel port.

## Keeping overhead down

- Create each pool once, at the start, with a deadline at the run's end, and set a floor of one
  node on the deciding machines, so a new experiment doesn't wait for a boot and start task.
- One task per experiment per machine. Queue the next experiment before the current one ends,
  so nodes don't sit idle between ticks.
- Take Cobalt 100 and any large node down as soon as their work is done; don't hold them to the
  deadline.

## Morning report additions

Besides the usual report (section 9 of `AUTOPILOT.md`):
- **Decisions and why**: for each experiment, one or two sentences on why you chose it, what
  you passed over, and how you made the call. Draw on the `st.py decide` records.
- The dry-run checks: what passed, what failed, what you changed.
- The overhead split for the run and the measuring share.
- Where the base entry stands against Rust and Swift on each machine, and against the official
  numbers.
