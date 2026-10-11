# Run plan: does the machine carry over? (agreed with Chris, 2026-10-11 10:45)

Read this after `AUTOPILOT.md`. It sets this run's priorities, time box and end-of-run steps.
Everything else in the brief, the runbook and `HILL-CLIMB.md` still applies, including the
"Never without Chris" list. The previous plan is in git history; its results are in the morning
report of run ap-20261010T2040Z in `STATUS.md`.

## Limits

- Time box: 4 hours from the session start. Stop starting experiments at 3h15, so the final
  scoreboard and shutdown fit in the last 45 minutes.
- Azure: NZ$30 for the run, no new pools past NZ$25, Spot only, 128 Spot vCPUs in all, at most
  6 pools. Every pool's deadline is the run's end; take a pool down as soon as its work is done.
- The 96-vCPU node waited 25 minutes for quota last run (backlog 29). If this run needs it,
  bring it up first, alone, then build the fleet around it.
- This run starts from a cleared conversation (Chris runs `/clear` before the kickoff), to test
  whether a fresh context cuts tokens per experiment. Everything you need is in git. Run
  `tools/tokens.py --role climber --status` at start-up and at shutdown; `tick.sh` runs it on
  every tick.

## State at the start

- `hc/champion` = `1551635` (clean); `hc/champion-grey` = `3a893c1` (clean + F1). The upstream
  question on F1 and F2 is drafted for Chris (`drafts/upstream-issue-F1-F2.md`); nothing grey
  goes near a submission.
- Zig: `hc/zig-submission` (clean), `hc/zig-champion-grey` = `72e5b42` (Zig base + F1).
- Ports, written once and never climbed: `hc/port-cpp-base` (PrimeCPP/solution_6),
  `hc/port-cpp-wheel` (solution_7), `hc/port-rust-wheel` (PrimeRust/solution_8),
  `hc/port-rust-base` (solution_9). Their last measurements against our ISPC entries, one
  thread: C++ base −4% Zen 5 / −8% Zen 3; Rust base −14% / −14%; C++ wheel −18% / −9%; Rust wheel
  −14% / −12%. The Rust base trails mike-barber's Rust by 8% to 11%.
- None of the ports has today's ISPC keeps (wheel-group32, IDEAS 12) or F1.

## Order: finish ISPC first, then climb the ports against it

**Phase 1, about the first 75 minutes: finish ISPC and freeze it.** Streams 2, 3 and 4 below run
first, on the fleet. Then run one final ISPC scoreboard, base and wheel, Zen 5, Zen 3 and Zen 4,
with per-thread columns, and tag the result `hc/ispc-ref` (clean champion). That tag is the
fixed reference every port is measured against in phase 2, so the port comparisons don't move
under the run. Meanwhile, background agents do stream 1's local work: port the ISPC keeps into
each port (step 1 below) and prepare the profiles (step 2). Nothing in phase 1 changes
`hc/champion` except a keep from F4.

**Phase 2, the rest: climb the ports** (stream 1), against `hc/ispc-ref`. If a phase 1 task
overruns, start phase 2 on the nodes that are free rather than wait.

## Stream 1 (main, phase 2): climb the three ports, the same way in each language

This run is the test in `docs/generalising.md` of the hill-climber repo: does the machine carry
over to new code without being rebuilt? Treat the three languages alike.

- **Branches.** Each port gets its own champion: `hc/port-<lang>-<design>-champion`, starting at
  the port branch above. Grey changes (F1) go on `hc/port-<lang>-<design>-grey` only.
- **Deciding machines and rule.** Zen 5 and Zen 3 decide, as for ISPC; the interval rule from
  `HILL-CLIMB.md`; Cobalt 100 gate for any change that touches Arm code; Zen 4 recheck for keeps.
- **Rivals in every round:** our ISPC entry of the same design at `hc/ispc-ref` (the reference ceiling) and the
  fastest existing entry in the port's language: mike-barber's Rust (`PrimeRust/solution_1`) for
  the Rust base; davepl's C++ (`PrimeCPP/solution_5`) for the C++ base; for the wheels, which
  have no rival in their own language, rogiervandam's C wheel.
- **Equal effort.** Aim for the same number of decided experiments in each of C++, Rust and Zig,
  about five each, base and wheel together. If one language runs ahead, feed the others first.
- **Order within each language:**
  1. Port the ISPC keeps it lacks (the porting rule): for the wheels, wheel-group32's loop shape
     where the compiler can express it, and IDEAS 12; for the bases, F1 on the grey branch only.
  2. Profile the port against our ISPC entry on one Zen 5 node, phase by phase, and compare the
     compiled hot loops (AUTOPILOT 2d). Name the gap before changing anything.
  3. Then the language's own ideas. For the Rust base, start with the side-by-side against
     mike-barber's entry (`results/hc/port-rust-base/README.md`): something his code does, ours
     doesn't, and his is faster. For the C++ wheel, start with the compiler (GCC against Clang,
     the same flags as the existing C++ entries) and the spill fix the last run found.
- **Zig:** the Zig wheel already beats our ISPC wheel at one thread on Zen 5 and Intel. Climb it
  like the others; if it passes the ISPC wheel by the keep rule, say so plainly in the report.
- **Record, for `docs/generalising.md`:**
  - set-up cost per language: what had to change in `hc-pool.sh` and the build, self-test and
    rules checks, with the commits;
  - per language: experiments decided, keeps, and the gap to our ISPC entry and to the language's
    best existing entry at the end;
  - for every experiment, whether the idea was carried over from ISPC, found in the language
    itself, or came from outside (`st.py decide` and the experiment's `plain` field);
  - which ISPC keeps helped in each language and which didn't;
  - node-minutes per language from `jobs.tsv`.

## Stream 2 (phase 1): rank the way the leaderboard ranks

The official multi-thread table sorts by passes per second per thread (`tools/src/formatters/
table.ts` upstream). mike-barber's Rust reports a 4-thread line, which tops that table; ours
reports one thread, then all, half and a quarter of the threads.

- Add per-thread columns (passes / duration / threads) to `analyze.py` and the scoreboard.
- Measure, on Zen 5 and Zen 3: our base and wheel at 4 threads against Rust's 4-thread line and
  the C wheel, per thread. A measurement, not an experiment.
- Put a 4-thread line on a branch (`hc/line-4t`) for both ISPC entries, built and self-tested,
  **not merged**: whether our entries report it is Chris's decision.

## Stream 3 (phase 1): a new rival wheel

PR #1094 upstream (crishoj, Zig, `PrimeZig/solution_5`, a 210-wheel) claims about 2.2 times the
existing Zig wheel. Build it from `pull/1094/head` (Zig 0.17, its own Dockerfile) and add it as a
second control in one wheel task on Zen 5 and Zen 3, beside our ISPC and Zig wheels: one
thread and all threads. A measurement only. Its faithfulness is not ours to judge in the run;
record the numbers.

## Stream 4 (phase 1): ISPC leftovers

F4 (`PRIMES_DENSE_MAX` 384, 512, 640, wheel), then F6 (AVX-512 off at 96 threads) if the 96-vCPU
node is up for something else anyway. Nothing grey this run beyond porting F1.

## Morning report additions

Lead with stream 1, as a table per design: ISPC, Zig, C++, Rust at the start and end of the run,
one thread and all threads, Zen 5 and Zen 3, with each language's best existing entry beside it.
Then the generalisation record above, then stream 2's per-thread table, stream 3's numbers, and
tokens per experiment for this run against the last two.
