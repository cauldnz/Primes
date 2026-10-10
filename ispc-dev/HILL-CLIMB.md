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
- Warm-up. Discard round 1 on every VM. On `D16as_v7` round 1 ran about 17% slow for every
  build (126k against 151k for the same binary), then settled.
- Rounds. At least five interleaved rounds per machine. Report the median and the range.
- Machines. Every decision needs Zen 3 and Zen 5 (`D16as_v7`). Use `D16a_v4` for Zen 3: on
  2026-10-09 `D16as_v5` landed on Zen 4 (EPYC 9V74, AVX-512 hidden) in all four runs, while
  `D16a_v4` gave an EPYC 7763 every time. Add
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

**Small consistent gains** (agreed with Chris, 2026-10-10). A change that misses 2% is still
kept if its ten-round rerun shows a median gain of at least 1% on both Zen 3 and Zen 5 (1T or
all threads), wins at least 8 of 10 rounds on each, and loses no more than 0.5% on any machine
or thread count (arm64 included, for shared code). Queue the rerun as soon as a six-round run
lands between 1% and 2% on both machines.

**Target-specific changes** (agreed with Chris, 2026-10-09). A change that alters the code for
some instruction sets only (for example `#if defined(ISPC_TARGET_AVX512SKX)`) is kept if it
gains at least 2% on the machines whose code changes, and the generated assembly for every
other target is byte-identical to the champion's. Show the identity with an `--emit-asm` diff.

**arm64 gate.** Any change to shared code or to a NEON target gets a Cobalt 100
(`D4ps_v6`) A/B run before it merges. On 2026-10-09 hc-002 merged without one and made the base
entry 39% slower on arm64, because ISPC's NEON target scalarised the vector dense code (fixed
by hc-020).

**SSE4.** For changes that touch SSE4 code paths, check the SSE4 build against the champion
locally (`ISPC_TARGETS=sse4-...`) before merging; the Celeron runner has nothing newer.

## Rules gate

Check this before timing, and again before merging:

- Faithful (both): all state is in `struct Sieve`; a new instance is allocated every pass;
  nothing persists between passes; no external dependency does the sieving.
- Base (solution_2): one operation per composite in the source; next-prime search over odd
  numbers from 3; no prime knowledge beyond 2 being even; no page segmentation.
- Wheel (solution_1): tags stay `algorithm=wheel`. If a change moves the design towards
  something a reviewer would call "other", stop and flag it.
- Read `ispc-dev/RULES-REVIEW.md` when unsure.

## Ledger

Append one row per experiment to `ispc-dev/results/hc/LEDGER.md`:

| id | date | entry | hypothesis | prediction | Zen 3 1T/16T (median, Δ) | Zen 5 1T/16T (median, Δ) | verdict | commit |
|---|---|---|---|---|---|---|---|---|

Then add a short note per experiment under the table: what happened, and what it suggests next.

## Budget and stop conditions

- Azure: prefer Batch Spot.
  Stop and ask Chris before spending more than NZ$50 in one session.
- Diminishing returns. Stop a line of attack after three experiments in a row on it fail the
  acceptance rule.
- Time box. Submission-readiness comes first (NEXT-STEPS tasks 3 and 4). Hill climbing runs
  after the PR is opened, or in parallel only if it doesn't block the PR.
- No pushes to `ispc` and no PR changes without Chris's explicit OK. Winners reach the PR
  through a follow-up commit he approves.

## Next run plan (agreed with Chris, 2026-10-09 21:30 AEST)

1. **Harness: persistent auto-scaling pools.** One Batch pool per VM size that lives for the
   whole run. Its autoscale formula follows the task queue
   (`min(cap, pending + running tasks)`), drops to zero nodes when the queue is empty, and
   drops to zero at a hard deadline whatever happens. A start task installs Docker and builds
   the controls (C5, Rust, Chapel, davepl C++) once per node. Experiments are submitted as
   tasks, not pools. That saves the 4–6 minutes of boot, apt and control builds each run paid
   today, and lets one size run several experiments at once. The runbook limit becomes "at
   most 8 nodes in total" instead of "at most 4 pools". The 50-minute cap per run becomes a
   per-task wall-clock limit.
2. **Controls: add davepl's C++ base** (`PrimeCPP/solution_5`, `davepl_array_optimized`) next
   to mike-barber's Rust for the base entry. Re-pull the full leaderboard JSON first; this
   morning's pull was truncated.
3. **Research pass 2**, from what this run learnt: what davepl's `mark_multiples` does; where
   our base can go past Rust on Zen 5 (both are now 38k dense and 61k sparse cycles a pass);
   L1 blocking under the base rules; why NEON scalarises the vector dense code and whether a
   NEON-friendly form exists (the Pi 4 is an official runner, and base is level with the start
   there); start-up autotune. External models (GPT, Gemini via Copilot) get the same brief
   through Chris; their replies are logged in `RESEARCH.md` with the source named.
4. **Rust: improve mike-barber's entry** (`PrimeRust/solution_1`). CONTRIBUTING.md asks for
   improvements to an existing solution when the approach matches, and it does. Work goes on
   `hc/rust-*` branches only, measured with the same A/B harness (candidate against upstream
   Rust, with our base entry as the control). Nothing is submitted without Chris and, per
   CONTRIBUTING.md, without contacting the author. Candidate ideas: the AVX-512 build (its
   `.cargo/config` disables `avx512f` for an Intel problem that may not apply on Zen), a
   pointer-walk sparse loop like hc-003, the dense limit (129), and a NEON check.
5. **Then the open decisions:** merge `hc/champion-plus-target-specific-2` if Chris agrees,
   and refresh the README and PR numbers.

## Backlog (ranked)

Seeded from today's results. Re-rank after each experiment.

### Base (solution_2): the biggest gap, so it goes first

On the 14:45 matrix the base entry trails mike-barber's Rust extreme-hybrid by 15% on Zen 3
(44.6k against 52.4k), 17% on Zen 4 (63.7k against 76.6k) and 31% on Zen 5 (87.3k against
126.5k). It trails GordonBGood's Chapel by 6–21%. On arm64 the gap is 4–5%. Both rivals use the
same dense and sparse scheme, so the gap is in the details.

Re-ranked on 2026-10-09 at 16:40 AEST from the hc-001 profile (cycles per pass at 1T; the gap to
Rust is 51k on Zen 4 and 49k on Zen 5).

1. ~~Profile against Rust~~ Done (hc-001). See "Where the cycles go" in `STATUS.md`.
2. ~~**Vector dense resets**~~ Done (hc-002, +22% to +24% at 1T). (At stake was 29k–35k.) Rust's dense phase is SLP-vectorised by
   LLVM; ours is scalar. Write the per-composite ORs per SIMD lane so LLVM folds them into
   constant vector ORs.
3. ~~**Dense limit with vector resets**~~ Parked: ISPC compile time explodes past factor 128. (At stake: about 10k.) Vector resets cost a flat ~2.2k
   cycles per factor up to 255; sparse ones cost 2.6k–3.3k for factors 131–251. Sweep 128, 160,
   192 and 256.
4. ~~**Sparse loop on Zen 5**~~ Done (hc-003 pointer walk, +12% on Zen 5; hc-018 two-chunk unroll, flat). (At stake was 15k on Zen 5, 8k on Zen 4.) Compare our loop's code with
   Rust's `chunks_exact_mut` loop: index width, address arithmetic, the tail.
5. **AVX-512 for the vector dense code** (hc-013: +1.0% on Zen 5; waiting for Chris) (at stake: part of item 2's remainder on Zen 5). One
   zmm per 8 words instead of two ymm.
6. ~~**Next-prime scan**~~ Tried (hc-009): slightly slower. (At stake: under 1k.) Word-at-a-time scan with count trailing zeros. Not
   worth an experiment on its own.
7. **Block the dense phase** in L1-sized chunks. Check against the base rules first.

### Wheel (solution_1)

Adopted from `RESEARCH.md` section 7 on 2026-10-09 at 16:50 AEST, ahead of the older items below:

- W-a. **No masked tails on AVX2.** hc-005 (all targets) lost 1.7% on Zen 5; hc-007 (AVX2 and SSE
  only) gained 4% to 5% on Zen 3 and Zen 4; waiting for Chris. Pad planes to 16 words and run lead-ins and tails unmasked.
  About 2,000 `vmaskmovpd` stores a pass, slow on Zen 2 to Zen 4. Predict +3–6% on the AVX2
  path; the `D16as_v5` nodes (Zen 4, AVX-512 hidden) run that path.
- W-b. ~~**One-member group fast path for 13.**~~ Done (hc-004, +5% to +9%). 13 costs about 9k cycles a pass on its own.
  Predict +3–4%.

1. ~~Zen 5 drift~~ Resolved: round 1 is a warm-up effect (see the evaluation protocol).
2. ~~Gang width on arm64~~ Done: `neon-i32x8` is now the arm64 default (+4% on Neoverse N1, +15%
   on N2).
3. **Fusion group size `G`** (now 8) against gang width. Sweep G over 4, 6, 8, 12 with
   avx2-i32x16 and avx512skx-x16.
4. **Dense threshold with the new gangs.** 256 was tuned on avx2-i32x8. Re-sweep 192–384.
5. **Pattern scratch size.** `Group` holds about 70KB, which spills a 32KB L1 on Zen 3 and Zen 4.
   Size the buffers to the largest dense prime actually used (now 256, not 1,024).
6. **Zen 4 margin.** On Zen 4 the wheel leads C5 by only 2% single-threaded (98.7k against
   97.0k). Items 3–5 matter most there. The official EPYC runner may sit on Zen 4 hardware.
7. **Sparse phase.** Large primes take roughly a third of the cycles. Try unrolling the
   eight-plane loop by two, and processing two primes per loop.
8. **Mod-210 wheel** (48 planes). It does less work per prime but has shorter planes. Prototype
   it on the sandbox first, because it's a large change.

## Writing

Anything committed to `PrimeISPC/`, the PR, or this branch's notes follows Chris's house style:
the `house-style` and `economist-style` skills. Load both
before writing a README, a PR description or a ledger note. Commit messages count too.
