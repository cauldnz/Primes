# Run plan: size, then a submission-ready finish (agreed with Chris, 2026-10-11 16:50)

Read this after `AUTOPILOT.md`. It sets this run's priorities, time box and end-of-run steps.
Everything else in the brief, the runbook and `HILL-CLIMB.md` still applies, including the
"Never without Chris" list. The previous plan (the ports run) is in git history; its results are
in the morning report of run ap-20261011T0100Z in `STATUS.md`.

## Limits

- Time box: 6 hours from the session start. Stop starting experiments at 5h15; the final
  scoreboard and shutdown take the last 45 minutes.
- Azure: NZ$25 for the run, no new pools past NZ$20, Spot only, 128 Spot vCPUs, at most 6 pools.
  Every pool's deadline is the run's end; take a pool down as soon as its work is done.
- Check the CPU model line of every log against the pool's intended chip before counting it
  (`D16as_v5` gave both Zen 3 and Zen 4 last run). A run on the wrong chip doesn't count.
- This run continues the last run's conversation (Chris, 16:41: no clear), so its tokens per
  experiment are a check on what clearing bought. Write a "Run ... started" event first thing
  (`st.py`), so the token counter can attribute the run, and report main-session and
  background-agent tokens separately.

## The keep rule for this run

Chris approved the per-thread rule (11 October, 16:50); it is now "Acceptance rule" in
`HILL-CLIMB.md`. Decide on passes per second per thread at 1T and at 4T on Zen 5 and Zen 3, with
Intel AVX2 and Cobalt as gates; all-threads is recorded, not decided. Say so in the first event.

## State at the start

- `hc/champion` = 330b3d4 (base 16-lane dense when a thread has a core; wheel start offsets on
  x86). Base +10.44% ± 0.11 over mike-barber's Rust at 1T on Zen 5.
- `hc/champion-tables` = 90e81f9 (wheel with build-time tables, permitted lineage).
- Port champions: `hc/port-cpp-wheel-champion` 547221c, `hc/port-rust-base-champion`; the rest
  as in last run's report.

## Phase 0, first 75 minutes: make the entries submission-ready

Chris's decisions of 11 October (`LAUNCH-PLAN.md`, step 0):

1. **4-thread line.** On `hc/line-4t` from `hc/champion`: an output line at exactly 4 threads in
   both ISPC entries, skipped when the machine has 4 or fewer hardware threads. Existing lines
   stay. Self-test, 6 rounds on Zen 5 (the 4T line's per-thread figure; no other line moves),
   merge, one README sentence per entry on why.
2. **Third entry, `PrimeISPC/solution_3`**, from `hc/champion-tables` plus the 4-thread line.
   Own output label (`cauldnz-ispc-wheel-tables`), tags `algorithm=wheel,faithful=yes,bits=1`.
   README words exactly as in `drafts/solution-3-notes.md`, and the one line for solution_1.
   Self-test, Dockerfile build, the 5,396-size sweep; 6 rounds against solution_1 on Zen 5 and
   Zen 3. Lives on `hc/champion-tables`, never on `hc/champion`.
3. **AVX-512 check of fold-1pc**: 6 rounds of base `hc/champion` against 1551635 on
   `Standard_D16as_v6` (Zen 4, AVX-512) and `Standard_D16s_v5` (Intel Xeon, native targets).
   1T, 4T and all threads. A loss of 1% or more at 1T or 4T: report, don't fix in this run.
4. **Clean the champion**: stop tracking build outputs (`primes`, `*.o`) on `hc/champion`.
5. **The verdict line**: `analyze.py` still prints its VERDICT by the old rule. Change it to the
   new one (1T or 4T per thread, both Zens, gates) before deciding anything, and backtest it on
   the last run's keeps and reverts; note any decision that would have gone the other way.

## Stream 1 (main): size

Every lead so far comes back to whether the working set fits the first-level data cache:
32 KB on Zen 3, Zen 4, the i7, the Celeron and the Pi 4; 48 KB on Zen 5; 64 KB on Cobalt. Four of
the five official runners have 32 KB. The base sieve is 62.5 KB at one million and the base rules
fix that. The wheel's eight planes are 33.3 KB, just over 32 KB, and each group pass also streams
its members' patterns (about 12 KB for six primes near 256) while sweeping all eight planes. So
the wheel probably fits on Zen 5 and spills on every 32 KB machine. This stream finds out, then
attacks it.

1. **Measure first: the size cliff.** Run each entry at sieve sizes from 250,000 to 2,000,000
   (about 12 sizes, closer together around 1M) on Zen 3, Zen 5 and Cobalt, one thread and one
   per core, 3 rounds. Plot throughput per number (passes × size / 5 s, normalised by
   n·log log n) against the working set in KB. A step where the working set crosses the L1 size
   is the prize; its height says what fitting is worth. Predict before running: the wheel drops
   10% to 20% between 0.9M and 1.1M on Zen 3 and not on Zen 5; the base drops 5% to 15% near
   0.77M (48 KB) on Zen 5. Write the result to `results/hc/size-cliff/README.md` with the chart
   data. This also gives the upstream F1/F2 question a clean number for what L1 is worth.
2. **Only if the wheel shows a cliff on Zen 3**, candidates, extra-faithful, each one change:
   - *Plane order*: alternate the plane order of successive group passes (0..7, then 7..0), so
     each pass starts on planes still in L1. This is wheel F1 restricted to the group passes;
     the earlier wheel F1 was measured on Zen 5 only, where nothing spills. Decide on Zen 3.
   - *Plane halves*: apply each group to planes 0-3, then rebuild nothing and apply it to 4-7;
     the patterns stay hot and the live planes halve to 16.7 KB. This is a form of segmentation:
     Chris wants to be asked before it is built. Report the case (the cliff, the prediction,
     the rules text) and work on the other candidates until he answers.
   - *Sparse marks plane by plane*: today each large prime advances all eight planes at once
     (eight streams for parallelism) and so touches all 33 KB. Do one plane at a time, taking
     the parallelism from several primes instead. Working set one plane, 4.2 KB.
   - *Trim the touched scratch*: patterns are stored extended by 64 words per member; check
     whether a 32-word extension (AVX-512 reads two vectors) is enough.
3. **For `solution_3`**: a pass reads about 60 KB of tables. Measure whether a compact layout
   (patterns without the 32-word extension, rotations computed) beats it on Zen 3.
4. **Base code size**: report the bytes of the hot dense and sparse code per target
   (`objdump`), the x16 copy included. If the dense switch is large, try a generic loop for
   factors 65 to 127, which is also the next Cobalt idea (no mask reloads).
5. **Grey, for the issue only**: F1 on top of 330b3d4, Zen 5 and Zen 3, 6 rounds, so the
   upstream question quotes F1's gain on the code we'd submit. Never merged.

## Stream 2: ports, with fixed shares

Last run equal effort didn't survive a change of priority. This time each language gets a
fixed share, whatever else happens: one agent slot in turn and at least three decided
experiments each.

- **Zig**: the wheel's group passes are 13% slower than ISPC's (profile of 11 October); start
  there. Then the Zig base, not climbed since the first runs.
- **Rust wheel** (24% behind ISPC on Zen 5): profile first, phase by phase against ISPC.
- **C++ base** (5% behind ISPC on Zen 5): the 16-lane idea from fold-1pc, if the compiler can
  express it; Clang lost 15% on this code, so check GCC's compiled dense loop first.
- Record for `docs/generalising.md`: experiments, keeps, gaps, node-minutes per language.

## Final scoreboard (last 45 minutes)

Per thread at 1T and 4T, all three ISPC entries, on Zen 5, Zen 3, Zen 4 with AVX-512 and
Cobalt, with mike-barber's Rust, danielspaangberg's C wheel and rogiervandam's C beside them;
the ports at 1T. Tag the result `hc/ispc-final` (both lineages: `hc/ispc-final` and
`hc/ispc-final-tables`). That tag is what the PR is built from.

## Morning report additions

Open with the size cliff chart data and what it says. Then the phase 0 results, stream 1 keeps
and rejects by kind, the ports table, the final per-thread scoreboard, tokens per experiment for
this run (main session and background agents separately).
