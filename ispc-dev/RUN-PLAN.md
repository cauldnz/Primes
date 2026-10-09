# Run plan: 4-hour unsupervised run (agreed with Chris, 2026-10-10)

## Next run (written at the end of ap-20261009T2033Z)

Run ap-20261009T2033Z worked through the plan below; its results are in the morning report
in `STATUS.md`. For the next run, in order:

1. **Rust port of the ISPC wheel** (Chris, 2026-10-10 08:20; see `NEXT-STEPS.md`): the same
   mod-30 planes, fused fixed-row patterns (as in hc-035) and interleaved sparse loop, on
   `hc/rust-wheel` branches, never touching mike-barber's solution. Same self-test and
   5,396-size count sweep. Measure it in the same rounds as the ISPC and Zig wheels. A `zig`
   task with `CTRL_REF` shows how to put two builds on one node; add a `rustwheel` kind.
2. **The Zig wheel's lead, continued.** Same-node profiles put it in sparse marking on Zen 5
   (24.0k against 29.9k cycles) and in both big phases on Zen 3. Loop shape (hc-042, hc-043),
   tails (hc-044) and start-bit arithmetic (hc-045) are tested. Untested: sparse per-prime
   set-up beyond `start_bit`, code alignment, and `-mcpu` tuning (hc-041: +3.7% at 1T, −3.1%
   at 16T on Zen 3, single target only). A diagnostic build that times the sparse set-up and
   the main loop separately is the next measurement.
3. Harness backlog items 3 (two-stage screen) and 4 (several candidates per task).

The plan for ap-20261009T2033Z follows, kept for the record.

Read this after `AUTOPILOT.md`. It sets this run's priorities, time box and end-of-run steps.
Everything else in the brief, the runbook and `HILL-CLIMB.md` still applies, including the
"Never without Chris" list.

## Limits

- Time box: 4 hours from the session start. Stop starting experiments at 3h15, so the final
  scoreboard (priority 4) and shutdown fit in the last 45 minutes.
- Azure: NZ$30 for the run, no new pools past NZ$25, Spot only, at most 4 pools and 8 nodes.
  Every pool's deadline is the run's end.
- If Azure login fails at start-up (the secret was rotated on 10 October), work in local mode
  and say so in the morning report.

## State at the start

- `hc/champion` = `4c7dc69`: everything accepted so far, including hc-035 (wheel, fixed-row
  patterns, +2% to +3.4% at all threads on Zen 3/4/5) and hc-028 (base, merged on Chris's
  decision: +4.2% Zen 5 1T, +1.3% Zen 3). Pin this hash as the champion for the run's first
  experiments; move the pin only when you merge a winner.
- Tools: `ispc-dev/hc-pool.sh` (persistent pools; see the runbook), `ispc-dev/hc-meter.sh`
  (cost), and in `ispc-dev/tools/`: `st.py` (edit `status.json`), `pub.sh` (commit, push,
  publish; set `TRAILER` to your commit attribution lines), `prun.sh` (queue one experiment in
  the background), `sweep_patch.py` + `sweep_check.py` (a 5,396-size count sweep of the wheel
  against a Python sieve; run it on every wheel change, for each target you touch).
- New acceptance rule for small gains: see "Small consistent gains" in `HILL-CLIMB.md`.

## First 40 minutes: improve the harness

Read `REVIEW-2026-10-10.md`, then do items 1 and 2 of `HARNESS-BACKLOG.md` while the pools
warm up: the phase-profile diagnostic builds (ours, the Zig wheel, and Rust for the base) and
danielspaangberg's best wheel as a rival in `hc-pool.sh`. Test each on one node before relying
on it. If a Spot node is preempted, salvage its rounds with `tools/salvage.py` instead of
rerunning. If there is time, item 3 (the two-stage screen).

## Priorities, in order

1. **Explain the Zig wheel's lead.** The Zig wheel (`hc/zig-champion`, `PrimeZig/solution_4`)
   has the same design as ours and is 12% to 18% faster at 1T. hc-033 (two gangs a step) lost,
   hc-035 (Zig's pattern addressing) won only 2% to 3%, and the sparse loops and allocation
   look alike in the assembly (LEDGER notes 033 and 035). Measure first: add phase timers
   (tile, 13, fused groups, sparse, candidate scan, count) to both wheels on a diagnostic
   branch that is never merged, run both on Zen 3 and Zen 5, and find the phase that differs.
   Then port what Zig does there, one change per experiment.
   Also on the wheel list, each needing a phase share first: the byte sparse kernel on Zen 5
   (it lost 9% only on the Xeon sandbox), and the wheel against danielspaangberg on every
   machine.
2. **Base against Rust on Zen 5 and arm64.** Re-measure the champion base against
   mike-barber's Rust first; hc-028 should have it level on Zen 5 at 1T. The dense limit is
   settled at 128 (hc-031, hc-036) and the sparse loop is store-bound (hc-032, hc-034); look
   elsewhere: the next-prime scan, set-up, and a NEON-friendly dense form for arm64.
3. **Rust and Zig.**
   - Rust: hill-climb on `hc/rust-*` branches as before. Hold: don't contact mike-barber,
     open issues or post anything upstream.
   - Zig: Chris wants it prepared as a third submission. Hill-climb it, then build
     `hc/zig-submission`: a branch off `origin/drag-race` (the upstream default branch) that adds
     only `PrimeZig/solution_<next free number>/` with the source, `Dockerfile`, README (house
     style; `WRITING.md`) and the output tags it has earned. Check `CONTRIBUTING.md` and the
     existing `PrimeZig` solutions for the required layout, and the faithfulness rules in
     `RULES-REVIEW.md`. Don't open a PR.
4. **Final scoreboard (last 45 minutes).** One full matrix: champion against the `ispc` branch's
   code and the rivals, on Zen 3, Zen 4 (`D16as_v6`), Zen 5 and Cobalt 100, 1T and all threads.
   Then:
   - refresh both `PrimeISPC` READMEs on `hc/champion` with the new numbers and mechanisms;
   - refresh the results table in `ispc-dev/PR-DESCRIPTION.md`;
   - build `hc/ispc-landing`: a branch off `origin/ispc` with one solution-only commit that
     copies `PrimeISPC/solution_1/` and `PrimeISPC/solution_2/` from `hc/champion`. Build and
     self-test it, push the `hc/` branch, and stop there. Chris lands it on `ispc` and edits
     the PR himself.

## Morning report additions

Besides the usual report (section 9 of `AUTOPILOT.md`):
- the phase table for both wheels, and what explains the Zig lead;
- the `hc/ispc-landing` commit hash and the exact command to land it on `ispc`;
- the state of `hc/zig-submission` and anything it still needs.
