# Status from the Claude Code session

Autopilot lock: ap-20261010T2040Z 2026-10-10T20:40Z




**Last updated:** 2026-10-10 22:30 AEST. Living file; earlier versions are in
`git log -p ispc-dev/STATUS.md`. Replies go in `ispc-dev/NEXT-STEPS.md`.

## Morning report: run ap-20261010T0715Z (17:15 to about 22:30 AEST, 10 October)

Six-hour run from RUN-PLAN.md: scaling, ports, the Zig gap and Intel. Spend about NZ$1.8 of
NZ$30; nodes busy 69% of node time (608 of 884 node-minutes), against 31% last run. All pools
deleted at the end. Nothing went to `ispc` or to a PR. Full tables:
`results/hc/run-ap-20261010T0715Z.md`.

### Waiting for Chris

1. **Merge the thread-count fix** (`hc/idea1-affinity`, 8fd7f1f): fast-forward `hc/champion`
   37e19c7 -> 8fd7f1f. Both entries take their thread count from the affinity mask, so a
   container limited with `--cpuset-cpus` is not oversubscribed. Level everywhere (quiet Zen 5
   96-vCPU node 0.0% to +0.9%, Zen 3, Zen 4, Cobalt 100 base -0.2% and wheel 0.0%). My push was
   blocked by the session's permission check: `git push origin origin/hc/idea1-affinity:hc/champion`.
2. **`hc/wheel-group32` (5a68114), keep or drop.** The wheel's AVX-512 group loop in Zig's form:
   32-word steps, unmasked, every member's row off one base register. Zen 5 +4.4% at 1T,
   +2.5% at 32T, 24 of 24 rounds (second run; the first, on the noisy 96-vCPU node, +3.7% to
   +4.0%). Zen 4 0.0% at 1T, +0.2% at 16T. AVX2 and SSE4 code byte-identical, so Zen 3, the
   EPYC runner and the i7 are unaffected. It fails the written target-specific rule only because
   Zen 4 runs the same code without gaining; the official Threadripper is Zen 5.
3. **Port routes** (CONTRIBUTING.md, new solution or improvement to an existing one), below.

### Scaling and the full-occupancy lead (priority 1; Chris's three tests)

The largest Zen 5 size Batch offers here is 96 vCPUs (D96as_v7, 48 cores x 2 SMT); there is no
128-vCPU size. Second, quiet node (A/A within 0.7%):

| Base | 1T | 48T | 96T |
|---|---|---|---|
| ours | 129.0k | 4.34M | 4.47M |
| mike-barber Rust | 126.3k | 3.32M | 4.02M |
| davepl C++ | 92.3k | - | 3.33M |

| Wheel | 1T | 48T | 96T |
|---|---|---|---|
| ours | 204.6k | 8.05M | 7.73M |
| C5 (rogiervandam) | 135.5k | 4.53M | 5.35M |
| danielspaangberg | 69.2k | - | 2.42M |

- The first node gave the same shape (base lead +28% at 48T, +9% at 96T). Our lead is largest at
  one thread per core and narrows with SMT: ours gains 3% (base) or loses 4% (wheel) from the
  second hardware thread; Rust gains 21%, C5 18-43%.
- **Phase profile at scale** (`mt-phases-96`): up to 48 threads every phase slows by the same
  factor (+15% at 24T, +45% at 48T); from 48 to 96, dense still gains 13% per core and sparse
  loses 9%. The sparse phase is what stops gaining: two 62.5 KB sieves overflow a 48 KB L1D in a
  store-bound loop.
- **Loaded one-thread test**: one thread loses 29% when the other 47 cores run a sieve (24% with
  a spin loop), against 31% per thread in the 48-thread profile. Up to one thread per core the
  drop is clock, not our code; Rust drops by the same proportion.
- **On the 16-core node** (D32as_v7) the picture is the same: our 32T lead over Rust (+14%) is
  ours gaining 8% from SMT while Rust loses 3%. Not placement: pinning, the stop flag, a malloc
  arena per thread, smaller code (avx2-i64x4) and sparse prefetch were all flat or worse.
- **In README terms:** our entry reports all, half and a quarter of the threads; on SMT machines
  the half line (one thread per core) is the one that carries it.

### One design in four languages (priority 2)

All four ports pass their self-tests in the image; hadolint clean (agents' runs); measured in the
same rounds as the ISPC entry.

| Port, branch | Zen 5 vs ISPC (1T / all) | Zen 3 vs ISPC | vs nearest upstream |
|---|---|---|---|
| C++ base, `hc/port-cpp-base`, PrimeCPP/solution_6 | -4% / -7.5% | -8% / -8% | vs davepl +30-40%; vs Rust Zen 5 +5%, Zen 3 -2% |
| Rust base, `hc/port-rust-base`, PrimeRust/solution_9 | -13% / -20% | -14% / -9% | vs mike-barber Zen 5 -12% / -5%, Zen 3 -8% / -4.5% |
| C++ wheel, `hc/port-cpp-wheel`, PrimeCPP/solution_7 | -18% / -14% | -9% / -7% | vs C5 +19-63% |
| Rust wheel, `hc/port-rust-wheel`, PrimeRust/solution_8 | -14% / -16% | -12% / -15% | vs C5 +12-50% |

Routes:
- **C++ wheel and Rust wheel:** new ground (C++ has no wheel; Rust's only wheel, solution_7, is
  8-bit). Both lead C5; the PR text must say why the Rust wheel is not an improvement to
  solution_7.
- **C++ base:** same characteristics as davepl's solution_5 and 30-40% faster; per CONTRIBUTING it
  goes to davepl as an improvement first, unless Chris argues it is a different design.
- **Rust base:** slower than mike-barber's entry on Zen 5 and Zen 3, though 5% faster on the local
  Xeon. Nothing goes to mike-barber until each change is measured inside his code on Azure. Its
  side-by-side is `results/hc/port-rust-base/README.md`. Rules question: its dense masks come from
  a compile-time table that sets one bit per composite, folded by rustc rather than LLVM.

### Zig wheel gap (priority 3)

- The node dump (`results/hc/asm-wheel`) shows Zig on Zen 5 compiles to 256-bit vectors only; its
  lead does not come from 512-bit loops. Our AVX-512 group loop in Zig's form is
  `hc/wheel-group32` (above).
- On the 96-vCPU node Zig leads at 1T (+2.4%) and ties at 24T; ours leads at 48T and 96T.
  On Intel (AVX2) the Zig wheel leads ours by 10%.

### Intel (priority 4): Xeon Platinum 8370C, every entry AVX2-only

| Entry | 1T | 8T | 16T |
|---|---|---|---|
| ours, base | 57.4k | 455k | 378k |
| Zig base | 57.7k | 456k | 374k |
| mike-barber Rust | 55.7k | 444k | 372k |
| davepl C++ | 40.5k | - | 337k |
| ours, wheel | 108.5k | 862k | 798k |
| Zig wheel | 119.3k | 952k | 875k |
| C5 | 81.4k | 649k | 604k |

Base leads Rust by 2-3%; AVX-512 is worth nothing to the base on this Xeon (native 57.5k).
SMT costs every entry here. The official i7 session (9749) is tabulated beside these numbers in
the run file.

### Final scoreboard (thread-count fix build against the rivals, 6 rounds)

| Machine | base vs Rust 1T / all | wheel vs C5 1T / all |
|---|---|---|
| Zen 5 (D32as_v7) | +0.9% / +14.4% | +50% / +34% |
| Zen 4 (D16as_v5) | +8.3% / +8.0% | +41% / +38% |
| Zen 3 (D16a_v4) | +6.9% / +4.9% | +71% / +74% |
| Cobalt 100 | -2.1% / -1.9% | no wheel rival built for arm64 |
| Intel AVX2 | +3.1% / +1.7% | +33% / +32% |
| Zen 5, 96 vCPU | +3.1% / +10.9% | +50% / +43% |

### Decisions and why

- **Phase A on 96 vCPUs**, not 128: no 128-vCPU Zen 5 size in this region.
- **IDEAS queue (Chris's 07:40 order):** thread count from the affinity mask (keep), pinning
  (flat at 48/96T, worse at 24T: revert; it also had to be rewritten for Azure's adjacent
  sibling numbering), stop flag (flat: park), AVX-512 off (lead holds without it: probe), arena
  count (flat: stop), sparse prefetch (-7% at 32T: revert), smaller dense code (flat: revert).
- **Wheel:** IDEAS 12 (fold 13 into the tile) positive on Zen 3 (+1.3-1.9%), Zen 4 and arm (+3%)
  but its Zen 5 interval never cleared +1% in 20 rounds: no keep, worth a recheck. G=8 with the
  new loop: -2.4% at 96T, revert.
- **Ports:** written by background agents; each verified here (build, self-test, sweep, diff)
  before measuring. The C++ wheel went back for tuning (GCC spilled the sparse loop's eight
  stream indices; four planes at a time fixed it).
- Every decision is in the page's log (`st.py decide`).

### Overhead

884 node-minutes, 608 of them in tasks (69%; target 60%). The 96-vCPU node took 269. No floor
nodes: pools scaled to zero between tasks, and each pool came down when its work ended.

## Morning report: run ap-20261010T0140Z (11:40 to 14:30 AEST, 10 October)

Base-first run under the new tick harness. One keep (arm), every RUN-PLAN priority answered,
a final base scoreboard, and an early shutdown at 04:26Z (planned end 05:40Z). Spend: about
NZ$2.1 of NZ$30. All pools deleted. Nothing went to `ispc` or to a PR.

### What changed

**p4-arm-dense is merged into `hc/champion` (`37e19c7`, with Chris's approval).** A NEON-only
dense resetter after Rust's: masks held in q registers, one period per run from P = 17, so the
loop is `ldp q` / `orr` / `stp q`. Cobalt 100, six rounds: +2.5% at 1T (95% CI +2.2% to +2.8%),
+2.9% at 2T and 4T, every round won. The x86 `--emit-asm` output is identical for all three
targets, so Zen 3, Zen 5 and the D16as_v5 recheck are met by identity. Rust's lead on arm falls
from 4.3% to about 1.9%.

### Final scoreboard: base entry (`37e19c7`) against mike-barber's Rust, same rounds

| Machine | 1T | all threads | source |
|---|---|---|---|
| Zen 5 (D16as_v7) | 124.9k, +0.8% | 988k, +13.9% | final5, 6 rounds (1T A/A SD 2.3%: noisy) |
| Zen 3 (D16a_v4) | 56.0k, +6.5% | 431k, +4.7% | final5, 6 rounds |
| Cobalt 100 (D4ps_v6) | 42.1k, -1.9% | 169k (4T), -1.5% | p4-arm-dense, 6 rounds |
| Zen 5, 32 vCPU | 127.0k, +4.3% | 1.98M, +14.4% | p6-scaling-32, 4 rounds |
| Zen 5, 64 vCPU | 129.7k, +2.7% | 3.66M, +14.3% (32T: +2.5%) | p6-scaling-64, 4 rounds |

Against Swift (`yellowcub_fahlman_striped_UInt8`) on our Zen 5: ours 126k, Swift 107k (+18%).
Against the official numbers: Swift's 122,869 on the Threadripper is not reproducible here; our
Zen 5 tracks the Threadripper for Rust within 2%, which puts our 1T within about 1-3% of Swift's
official figure. That gap is machine or toolchain, not a phase we can see (below).

### Findings

- **The all-threads lead is a full-occupancy effect.** With threads equal to vCPUs (16/16,
  32/32, 64/64) we lead Rust by 14%; with vCPUs to spare (32 of 64) by 2.5%. Rust falls back
  when every vCPU is busy; ours keeps scaling. The official ranking runs all threads.
- **Swift's lead is not in the code.** Same-node profile: Swift is slower in every phase
  (sparse 29.8 vs 24.1 us, dense+scan 17.1 vs 15.6). Its striped layout still does one byte RMW
  per composite.
- **The compiled sparse loops** (`results/hc/asm-sparse/README.md`, Chris's request): ours and
  Rust's are the same 12 instructions per 8 bits (one `orb` RMW per composite, the floor under
  the base rules for p >= 113); Swift's is 25 per 16 with 6 spilled pointer reloads. llvm-mca
  (znver4, a screen) 0.67 / 0.67 / 0.81 cycles per bit. No sparse-loop change is supported; any
  gain left is in the memory system (a perf-counter run would tell).
- **Stand-in:** D16as_v5 ran Rust 5.6% below the EPYC VM, outside the 5% bar; Zen 3 stayed the
  decider, with Chris's D16as_v5 recheck for every keep.
- **SSE4 (Celeron path):** our `sse4-i32x4` build ties Rust's x86-64-v2 build at 1T (-0.7%) and
  trails 1.8% at 16T. `sse4-i32x8` is 12x slower (scalarised 64-bit lanes): reverted.
- **Arm phases:** the gap was in dense (ours 36.5 us vs Rust about 30), which p4-arm-dense
  targeted. The follow-up (factor 3 initialises the buffer on NEON) gained +0.5%: reverted.

### Decisions and why

- **p1 stand-in:** kept D16a_v4 as decider because D16as_v5 missed the 5% bar; passed over
  switching on a near miss.
- **p2 profiles first:** every later hypothesis named its phase; the base profile put sparse at
  61% on Zen 5 and near the store limit, so p3 waited for evidence.
- **p3 parked:** Swift profile and asm both showed no lever; passed over a blind Zen 5 1T change.
- **p4 arm:** the profile named dense; an agent wrote the NEON resetter; kept on the
  target-specific rule (lower bound +2.2% >= 2%, x86 asm identical). init3 failed the 2% bar.
- **p5 SSE4:** tied Rust; i32x8 probe reverted. An Intel proxy needs Chris's OK.
- **p6 scaling:** 32 then 64 vCPUs, one large node at a time inside the quota.
- **Early stop:** no candidate could finish six rounds plus the D16as_v5 check before 04:55.

### Dry-run checks (first two ticks)

All four passed: submit appears in `jobs.tsv` and partial output is copied; final output comes
from blob storage and the job is marked done; tally moves spend on the page; the `send_later`
wake-up fires and the tick resumes from git and Batch. Faults seen later: one submit failed
silently (caught by checking `jobs.tsv`, resubmitted); transient Azure connection resets
(retried); one tick.sh took 7 minutes on blob deletes; the 13 MB asm dump went into git via
`git add ispc-dev` (backlog 23); `jobs.tsv` records pool ids (backlog 22).

### Overhead

568 node-minutes (cost log) for 17 tasks totalling 174 task-minutes: tasks occupied 31% of
node time, short of the 60% measuring target. The split between builds and measuring inside a
task was not recorded. The rest is boot, start task and idle floor nodes (the Zen 5 pool held
two nodes for much of the run). Next run: floors of zero between bursts, or queue the next
experiment before the current one ends.

## Morning report: run ap-20261009T2033Z (06:33 to 10:00 AEST, 10 October)

Four hours from RUN-PLAN.md, on a fresh 10-hour secret. One big win, a final scoreboard, a
landing commit for `ispc` and a Zig submission branch. Spend: NZ$3.37 of NZ$30. All pools
deleted at the end. Nothing went to `ispc` or to a PR.

### What changed

**hc-045 is merged into `hc/champion` (code `059b8f3`, READMEs `a1433d9`).** `start_bit` now
uses unsigned arithmetic, as the Zig port does. Signed division and remainder by 30 each need
a sign fix-up, and the function runs about 1,300 times a pass. Wheel, 1T / all threads, every
round won: Zen 3 +10.3% / +5.9%, Zen 5 +9.0% / +5.2%, Cobalt 100 +4.5% / +4.4%. A follow-up making the rest of the wheel's divisions unsigned (hc-046) was flat: the cost was all in `start_bit`.

### Final scoreboard (`hc/champion` against the start, same rounds, six rounds)

| Machine | wheel 1T / all | change | base 1T / all | change |
|---|---|---|---|---|
| Zen 3 (EPYC 7763) | 110.1k / 939k | +35.7% / +33.8% | 56.0k / 432k | +25.3% / +26.0% |
| Zen 4 (EPYC 9V74, AVX-512) | 120.9k / 1.01M | +21.5% / +21.2% | 82.9k / 656k | +30.0% / +31.9% |
| Zen 5 (EPYC 9V45) | 207.6k / 1.57M | +38.0% / +26.6% | 128.1k / 1.02M | +48.0% / +47.7% |
| Cobalt 100 (arm64) | 98.5k / 393k | +55.6% / +55.5% | 41.1k / 164k | +0.2% / +0.1% |

Against the rivals at 1T: the wheel runs 2.3 to 3.0 times danielspaangberg's `5760of30030`
(the faithful wheel category's leader, measured for the first time) and leads rogiervandam's C
by 25% to 69% on Zen. The base leads mike-barber's Rust by 6.6% (Zen 3), 8.3% (Zen 4) and 2.0%
(Zen 5), 15.8% at all threads on Zen 5, and trails it by 4.3% on Cobalt 100. It leads davepl's
C++ by 28% to 54%. Both READMEs on `hc/champion` and `PR-DESCRIPTION.md` carry these numbers.
Logs: `results/hc/final4-wheel/`, `results/hc/final3-base/`.

### Landing on `ispc` (your step)

`hc/ispc-landing` is `77a197b`: `origin/ispc` plus one solution-only commit that copies
`PrimeISPC/solution_1/` and `PrimeISPC/solution_2/` from `hc/champion`. Both self-tests pass.
It is a fast-forward, so landing it is one command:

    git push origin origin/hc/ispc-landing:ispc

Then update the PR text from `PR-DESCRIPTION.md`.

### Is the Zig wheel's lead explained?

Partly. Same-node phase profiles found it in sparse marking on Zen 5 and in both big phases
on Zen 3. Reading the Zig source line by line found hc-045. After it, the Zig wheel's lead fell
from 15–19% to 7.6% on Zen 3 and from 10–13% to 4.6% on Zen 5 (same node, four rounds). Loop
shape (hc-042, hc-043) and tail handling (hc-044) are not the rest.

Proposed framing for the READMEs and the PR, for you to choose:
- "The design wins; ISPC made it quick to find; the Zig port shows it transfers." It is true
  as measured: the same design leads danielspaangberg's wheel by 2.3 to 3.0 times in both
  languages, and Zig's remaining lead is a few per cent.
- Or hold the "Why ISPC" section until the Rust port (next run) gives a third data point.

### The rest of the run

- Rejected: hc-042 (two gangs again, flat), hc-043 (Zig's sparse loop form, −3% to −19%),
  hc-044 (branch-free tails, −1% to −2%). Probe hc-041 (`--cpu=znver3`): +3.7% at 1T and −3.1%
  at 16T on Zen 3, single-target only.
- hc-028 confirmed: +0.7% Zen 3, +2.8% Zen 5, all rounds won.
- Zig: z05 (hc-026 ported) missed the small-gain rule (Zen 5 +0.6% over ten rounds).
  `hc/zig-submission` (`2de555d`) is `drag-race` plus `PrimeZig/solution_4`. It still needs a
  hadolint run and should go after the ISPC PR, because its README links to the ISPC entries.
- Harness: danielspaangberg is now the wheel's second rival; standing phase profiles for both
  wheels; `tools/salvage.py` and `tools/loopstat.py`; a fix to `tools/prun.sh`, whose shared
  script copy killed one task. The session's worker restarted once at 22:53 UTC; the Batch tasks
  carried on and nothing was lost.
- Calibration: 1 of 6 predictions in range (z05, on Zen 3 only). hc-042, hc-043 and hc-044
  were predicted to gain and lost or stayed flat; hc-045 was predicted at 0–2% and gained 9–10%.
  The profile found the right phase; my guesses about the mechanism inside it were wrong.

### Decisions for you

1. Land `hc/ispc-landing` on `ispc` and update the PR.
2. The Zig framing above.
3. The Intel proxy size (`HARNESS-BACKLOG.md` item 6) and a Raspberry Pi 4 run, both still open.

## Chris's decisions, 2026-10-10 morning

- **hc-028 merged** into `hc/champion` (now `4c7dc69`; both self-tests pass).
- **`ispc` after the next run:** the run ends with a full scoreboard and a ready commit on
  `hc/ispc-landing`; Chris lands it on `ispc` and edits the PR.
- **New acceptance rule** for small consistent gains (at least 1% on Zen 3 and Zen 5 in a
  10-round rerun, 8 of 10 rounds won): `HILL-CLIMB.md`.
- **Zig:** prepare it as a third submission (`hc/zig-submission`).
- **mike-barber:** hold; no contact yet.
- **Next run:** 4 hours, NZ$30; plan in `RUN-PLAN.md`. It needs a new session, because the
  Azure secret expired at 03:34 AEST and the rotated one only reaches a new session.

## Morning report: run ap-20261009T1349Z (23:49 to 02:25 AEST)

You asked for experiments from the two reviews (GPT-6 and Grok 4.7) until the Azure secret
expired. Eleven ran and one won. Spend: NZ$2.77. Nothing went to `ispc` or to a PR. All pools are
deleted and the meter is stopped; `az batch pool list` is empty.

### What changed

**hc-035 is merged into `hc/champion` (now `dc5fa37`).** The wheel's fused loop now reads each
prime's pattern from its fixed row of the group buffer, with 64-bit phases, instead of through
eight pattern pointers. That is how the Zig wheel addresses its patterns. On AVX2 the loop
went from 139 to 115 instructions a step and its stack reloads from 23 to 12.

| Machine | 1T | all threads | rounds won (all threads) |
|---|---|---|---|
| Zen 3 (EPYC 7763) | +1.6% | +3.4% | 10/10 |
| Zen 4 (EPYC 9V74, AVX-512) | +1.1% | +3.2% | 6/6 |
| Zen 5 (EPYC 9V45) | +0.5% | +2.0% | 9/9 |
| Cobalt 100 | −0.3% | −0.2% | n/a |

Zen 5 Spot preempted both nodes during round 10 of the confirmation, so its row is nine rounds
(`results/hc/hc-035-r10/`). The `hc/champion` README has one new sentence on the change.

### What didn't, and what the reviews got wrong

Both reviews put "raise the base's dense limit to 192–256" first and predicted +5% to +13% on
Zen 5. It goes the other way. With the masks still folding to constant ORs, dense to 191 lost
7% on Zen 5 (hc-031), and the same change in Rust lost 26% (r06). Dense to 96 lost 2.5% on
Zen 3 (hc-036). So 128 is right for both entries. AVX2 and SSE4 stop folding past 119, which is
why `VEC_LIMIT` exists.

- hc-030, wheel scratch from 70KB to 20KB (both reviews, +3–8% predicted): flat. Each row only
  ever touched L + 16 words, so the live footprint was already small.
- hc-032, immediate sparse offsets (Grok): flat; the loop is store-bound. hc-034, a counted
  sparse loop (Grok), was dropped on the assembly alone: the champion loop is already shorter.
- hc-033, two gangs per step as Zig does: −4% on Zen 5, −3% on Cobalt 100 (more spills).
- hc-037, G = 8 on AVX-512 on top of hc-035: −4.8% on Zen 5. G = 6 stays.
- hc-038 and hc-039, wheel dense limit 192 and 320: −1.7% and −6.9% on Zen 3. 256 stays.
- r07, a pointer walk in Rust's sparse loop: flat. `chunks_exact_mut` already compiles to one.

Rows and notes are in `results/hc/LEDGER.md` (030 to 039, r06, r07).

### Still open

- The Zig wheel is still 12% to 18% faster than ours with the same design. hc-035 copied its
  group-loop addressing, and its sparse loop and allocation now look like ours in the assembly,
  so I haven't found the rest. A phase-split timer run on both would settle it.
- Your earlier decisions stand: merge `hc/026-base-init-with-3`, move `hc/champion` onto
  `ispc` (it now includes hc-035), contact mike-barber, Zig as a third entry, and the rule for
  small consistent gains (hc-030 and hc-032 gained 0.1% to 1.3% at 1T and won most rounds).

## Morning report: run ap-20261009T1115Z (21:15 to 23:50 AEST)

Chris asked for six things and three hill climbs. Nothing went to `ispc` or to a PR. Spend:
NZ$3.82 of NZ$30. No pools are left running.

### The six items

1. **Merged** hc-019 (unmasked stores on AVX2 and SSE, G = 6 with AVX-512) into
   `hc/champion`.
2. **Merged** hc-013 (AVX-512 x8 target for the base entry).
3. **Fixed** both READMEs on `hc/champion` (`f43fe8b`): new mechanisms, Zen results tables and
   Output from Zen 5. `PR-DESCRIPTION.md` has its results table. The `ispc` branch still holds
   the old code; moving `hc/champion` onto it is your call.
4. **Docs**: the target-specific acceptance rule, the arm64 gate and the SSE4 check in
   `HILL-CLIMB.md`; a size-to-CPU table and the persistent-pool workflow in
   `CLOUD-RUNBOOK.md`; pinned `BASE` in `AUTOPILOT.md`.
5. **solution_3**: skipped, recorded in `RESEARCH.md`.
6. **davepl's C++** (`PrimeCPP/solution_5`) runs as a rival in every base run, at 1T and all
   threads. It is not the top base entry: we lead it by 34% to 52% at 1T on Zen, 28% on Cobalt
   100, and 34% to 42% at all threads. A full leaderboard pull (`results/leaderboard-2026-10-09b.md`)
   shows mike-barber's Rust tops the faithful 1-bit base table on all five runners except one
   cell, Threadripper 1T, where a Swift entry leads it by 3.4%. davepl reports only an
   all-threads line and ranks fifth there.

### Final scoreboard (`hc/champion` against the start of the evening, same rounds)

Passes in 5 s, median of five interleaved rounds, 1T / all threads, change against the start
of the evening (`ispc-dev` code) measured in the same rounds. Logs in `results/hc/final2-*`.

| Machine | wheel | change | base | change |
|---|---|---|---|---|
| Zen 3 (EPYC 7763) | 103.5k / 850k | +24.6% / +21.0% | 58.1k / 428k | +24.1% / +24.9% |
| Zen 4 (EPYC 9V74, AVX-512) | 115.1k / 953k | +15.5% / +13.5% | 81.4k / 650k | +27.9% / +30.5% |
| Zen 5 (EPYC 9V45) | 191.0k / 1.47M | +27.2% / +18.4% | 122.7k / 996k | +40.5% / +44.7% |
| Cobalt 100 (arm64) | 94.4k / 377k | +49.2% / +49.4% | 41.1k / 164k | −0.2% / +0.2% |

The "start of the evening" is the code at the start of *this afternoon's* run too: `ispc-dev`
never received solution changes. The wheel leads rogiervandam's C by 55% (Zen 3), 19% (Zen 4)
and 37% (Zen 5) at 1T. The Cobalt 100 wheel gain (+49%) is the largest; the self-test passes
there, but my wider count sweep only ran on x86 targets, so check it on arm64 before relying on
it.

### 7a: ISPC against the top base entry

The top base entry is mike-barber's Rust. Ours now beats it by 6% at 1T on Zen 3 and Zen 4,
trails by 3% at 1T on Zen 5 and leads by 14% at all threads there; on Cobalt 100 it trails by
4%. This evening's base experiments:

- hc-024 (`unmasked` in `clear_factor`; the dense code carried 13,924 masked moves) and hc-026
  (the factor-3 pass initialises the sieve): together +4.2% at 1T on Zen 5 and +1.3% on Zen 3
  (hc-028). That just misses "2% on both machines". **Your call; I recommend merging
  `hc/026-base-init-with-3`**: it puts the base level with Rust on Zen 5 at 1T as well.
- Rejected: dense pointer walk (hc-023), NEON vector dense (hc-025).

### 7b: Rust

`hc/rust-champion` = upstream plus r-01 (AVX-512 allowed): +2.4% at 1T and +4.9% at 16T on
Zen 5, identical code on Zen 3. On Zen 4 with AVX-512 it measured −0.5% at 1T (within the 1% limit). That is most of the 3.4% the Swift entry leads by on
the Threadripper at 1T. Rejected: a newer toolchain (r-02, −2.2%; with AVX-512, r-05, −62% on
Zen 5), 64-byte alignment (r-03), a pointer-walk sparse loop (r-04, flat under Rust 1.57).
Nothing goes upstream without you, and CONTRIBUTING.md expects us to contact mike-barber first.

### 7c: Zig first pass

`hc/zig-first-pass` adds `PrimeZig/solution_4` (Zig 0.13 from Alpine 3.21, built for the
native CPU like the C++ and Rust entries), one program with a base and a wheel entry.
- The **Zig wheel is our fastest wheel**: +18% at 1T on Zen 3, +13% on Zen 5 and +12% on
  Cobalt 100 over the ISPC wheel; +10% at all threads. It is a port of the ISPC design. Why it
  wins is open: the loop width isn't it (hc-027 lost), and short groups don't occur.
- The Zig base, after z-04 (64-byte-aligned sieve, leaner sparse loop: +15.5% on Zen 3, +9.1%
  on Zen 5), sits 3% behind our ISPC base on Zen 3 and 1.5% behind on Zen 5 at 1T, 1.6% ahead
  at 16T on Zen 5, and 50% ahead of davepl. It is on `hc/zig-champion`.
- One faithfulness point for you: each thread allocates from an arena that it resets after
  every pass (musl's malloc cost 20%). Every pass still builds a fresh sieve and writes all its
  memory before reading it. The README says so.

### Waiting for you

1. Merge `hc/026-base-init-with-3` (hc-024 + hc-026) into `hc/champion`? Recommended.
2. Put `hc/champion` on `ispc` and post the PR, with the new READMEs and table.
3. The Rust line: approach mike-barber with r-01, or keep going first?
4. Zig: a third language entry with a fast wheel. Keep developing it, and submit it?
5. Rule tweak: 1% to 2% gains that win every one of ten rounds with a tight A/A spread (hc-024
   on Zen 5) can't pass "2% on both machines". Keep the rule or relax it?

### Also tried tonight and rejected

hc-027 (wheel fused loop two vectors a trip, −6% on Zen 5), hc-029 (ISPC 1.28 on Ubuntu 26.04:
no gain for either entry), plus the Rust and base rejections above. All are in the ledger.

### Next three experiments

1. Find the Zig wheel's edge (allocation per pass in ISPC, LLVM 18 against 17) and port it.
2. Zig base: the remaining 3% to 7% gap to the ISPC base, then AVX-512 dispatch for Zig.
3. Rust: the Threadripper 1T cell (Swift, +3.4%); measure r-01 on a Threadripper-like Zen 5 and
   look for another 1%.

### Why the run stopped early

I stopped at 23:50 AEST, about 1.5 hours inside the time box: every line Chris asked for has a
measured result, the final scoreboard is in, and the open items need his decisions.


## Morning report: autopilot run ap-20261009T0607Z (16:07–21:05 AEST)

Nothing went to `ispc` or to a PR. Accepted changes are on `hc/champion` (`c48a327`); review
them with `git diff origin/ispc-dev origin/hc/champion -- PrimeISPC`. Spend: NZ$4.02 of the
NZ$30 cap. No pools are left running.

### What changed, measured against the start of the run

Final runs: `hc/champion` against the `ispc-dev` code, same node, interleaved, five counted
rounds, median, 1T / all threads. The x86 runs used `64e94aa`; hc-020 then changed NEON code
only, and the Cobalt 100 base row is from its run. Raw logs in `results/hc/final-entry1/` and `final-entry2/`.

Wheel (solution_1), 1T / all threads (16, or 4 on Cobalt 100):

| Machine | start of run | `hc/champion` | change | rogiervandam C5 | lead over C5 |
|---|---|---|---|---|---|
| Zen 3 (EPYC 7763, AVX2) | 80.7k / 702k | 98.2k / 832k | +21.7% / +18.6% | 65.2k / 533k | +51% / +56% |
| Zen 4 (EPYC 9V74, AVX-512) | 99.5k / 838k | 112.2k / 947k | +13.0% / +12.8% | 97.1k / 770k | +16% / +23% |
| Zen 5 (EPYC 9V45) | 150.6k / 1.24M | 179.6k / 1.47M | +19.5% / +18.3% | 139.5k / 1.19M | +29% / +24% |
| Cobalt 100 (arm64) | 63.3k / 253k | 77.1k / 308k | +21.9% / +21.8% | n/a | n/a |

On Zen 4 the wheel led C5 by 2% at 1T this morning (objective 2); it now leads by 16%.

Base (solution_2), 1T / all threads:

| Machine | start of run | `hc/champion` | change | mike-barber Rust | against Rust |
|---|---|---|---|---|---|
| Zen 3 (EPYC 7763) | 46.8k / 342k | 58.2k / 428k | +24.1% / +24.9% | 55.3k / 411k | +5.4% / +4.0% |
| Zen 4 (EPYC 9V74, AVX-512) | 63.7k / 497k | 82.0k / 650k | +28.7% / +30.7% | 76.5k / 607k | +7.1% / +7.0% |
| Zen 5 (EPYC 9V45) | 86.1k / 687k | 123.3k / 987k | +43.1% / +43.8% | 125.3k / 873k | −1.6% / +13.1% |
| Cobalt 100 (arm64) | 41.0k / 164k | 41.0k / 164k | −0.0% / +0.2% | 42.9k / 171k | −4.3% / −4.3% |

On arm64 the base entry is where it started, 4% behind Rust; the NEON target can't use the
vector dense code (see hc-020 below).

This morning the base entry trailed Rust by 15% on Zen 3, 17% on Zen 4 and 31% on Zen 5
(objective 1). It now leads on Zen 3 and Zen 4 and is level on Zen 5 at 1T. On Zen 5 the Rust
control ran at 125k in two rounds and 92k–96k in three; the table uses its full-speed rounds.

The SSE4 builds of both entries also beat the start of the run on the local Xeon (base +3% to
+27%, wheel +20% to +29%, three rounds each), which covers the Celeron runner's instruction set.

Commits on `hc/champion`, with each one's own gain (details in `results/hc/LEDGER.md`):

- Base `164f8c1` (hc-002): dense resets written per SIMD lane, folded by LLVM into vector ORs
  with constant masks. +22% to +24% at 1T on Zen 3, 4 and 5. Each composite still has its own
  single-bit OR in the source.
- Base `d04dc08` (hc-003): pointer walk over sparse chunks. Zen 5 +12.3% at 1T, Zen 4 +3.6%.
- Wheel `b1cd5c4` (hc-004): the lone prime 13 skips the fused loop. +4.9% to +8.7% at 1T.
- Wheel `51f0694` (hc-006): `--addressing=64`. +2% to +4%.
- Wheel `5667529` (hc-015): 64-bit sparse indices without a register spill. +5% to +7% at 1T
  and 16T on Zen 3 and Zen 5.
- Wheel `a1a5fad` (hc-016): no lead-ins in the fused group loop. +5% on Zen 3, +2.6% on Zen 5.
- Base hc-020 (merge after `64e94aa`): the scalar dense routine on NEON. My miss: I didn't run
  arm64 for hc-002 and hc-003, and the final scoreboard showed the base entry 38.9% slower on
  Cobalt 100. ISPC's NEON target turns the vector dense code into per-lane loads. With the fix,
  Cobalt 100 is level with the start of the run; the x86 assembly is unchanged.

### Waiting for you

1. **`hc/champion-plus-target-specific-2`** (hc-019): hc-007 (unmasked stores on AVX2 and SSE
   only) plus hc-014 (G = 6 with AVX-512 only) on top of the champion. Zen 3 +1.1% / +2.3%,
   Zen 5 +6.4% / +1.6%, +7% to +8% at 4 and 8 threads on Zen 5; Zen 4 with AVX-512 +4.3% at 1T
   for hc-014 alone. It passes the acceptance rule as one change, but the brief says to combine
   winners only after each passes alone, and each touches one instruction set only, so neither
   can show 2% on both Zen 3 and Zen 5. I recommend merging it. A rule for target-specific
   changes would help: at least 2% on the machines whose code changes, and byte-identical code
   on the others.
2. **hc-013** (base): add `avx512skx-x8`. +1.0% at 1T on Zen 5, every round. Small; your call.
3. **The README and PR numbers** for both entries are now stale. I haven't touched them.
4. **`D16as_v5` no longer means Zen 3**: it landed on Zen 4 (EPYC 9V74, AVX-512 hidden) in all
   four runs today, while `D16a_v4` gave a 7763 every time. I noted this in HILL-CLIMB.md; the
   example in CLOUD-RUNBOOK.md still uses v5.
5. **A third entry ("other" lane)**: the research agent recommends against building
   solution_3 now (RESEARCH.md section 6). Our wheel already beats rogiervandam's C at 1T on
   every Zen; a third entry would rank below it and draw scrutiny before the first two merge.

### Queue

`AZURE-QUEUE.md` is empty: this run was in Azure mode throughout.

### Next three experiments

1. Autotune at start-up (RESEARCH.md idea 5): time two or three settings of G, the dense limit
   and the gang before the timed loop, as C5 does. It would settle the target-specific question
   on unknown runners too.
2. Wheel: arithmetic masks for some fused-group members (RESEARCH.md idea 7), to balance load
   and ALU ports. The fused groups are 35% of a Zen 5 pass.
3. Base: past parity with Rust, the next lever is new: blocking the dense phase in L1-sized
   chunks (HILL-CLIMB base item 7), checked against the base rules first.

### Why the run stopped early

I stopped at 21:05 AEST, three hours inside the time box. The final scoreboard was measured
and a new merge would have made it stale. The last two Azure experiments (hc-017, hc-018) and a
local one (a faster pattern build) failed. The remaining backlog items each need about a day
(start-up autotune, arithmetic masks) or your decision (hc-007, hc-013, hc-014).


## Changes since last update

**Autopilot run ap-20261009T0607Z (16:07–21:05 AEST, finished; see the morning report above).** Details per experiment
are in `results/hc/LEDGER.md`; the page at https://cauldnz.github.io/Primes/ has the live state.

- Base entry (on `hc/champion`): vector dense resets (hc-002, +22% to +24% at 1T) and a
  pointer-walk sparse loop (hc-003, +12% at 1T on Zen 5). It now beats mike-barber's Rust at
  1T on Zen 3 and Zen 4, matches it on Zen 5 (124.5k against 126.0k) and leads at 16T on Zen 5
  by 13%.
- Wheel entry (on `hc/champion`): lone-prime path for 13 (hc-004), 64-bit addressing (hc-006),
  a spill-free sparse loop (hc-015) and no lead-ins in the group loop (hc-016). Each gained 2%
  to 9% on its own.
- Waiting for Chris: hc-007 and hc-014 (wheel) and hc-013 (base) change one instruction set
  only, so they can't meet the "2% on both Zen 3 and Zen 5" rule. hc-019 measures hc-007 and
  hc-014 together on the current champion.
- `D16as_v5` now lands on Zen 4 (EPYC 9V74, AVX-512 hidden). `D16a_v4` gives a Zen 3 (7763).

Earlier entries:

- NEXT-STEPS tasks 1 and 2 are done. The tables are below and the raw logs are in
  `results/azure-202610091445/`. Machines: Zen 3, Zen 4, Zen 5, Ampere Altra and Cobalt 100,
  all on Batch Spot.
- Target decision for x86: keep `sse4-i32x8,avx2-i32x16,avx512skx-x16`.
- Target decision for arm64: switch the default to `neon-i32x8`. It gains 4% on Neoverse-N1 and 15% on Cobalt 100.
- HILL-CLIMB backlog item 1 (the Zen 5 drift) is explained. The code didn't regress: the old and
  new builds measured within 1% of each other in the same round, on two separate Zen 5 nodes.
  The drift comes from the machine, and C5 drifts too.
- solution_2 builds and passes its self-test (13 of 13) on arm64, on both Ampere and Cobalt 100.
  This closes the open cell in `RULES-REVIEW.md`.
- A correction to `HILL-CLIMB.md` base item 1: the Rust run did not fail. All three rounds are
  in the 14:45 logs (they were still partial when you read them).
- Times here are now AEST, as you asked.


## Autopilot hourly review

**Run ap-20261009T1115Z, 22:40 AEST (hour 1.5).**
- Worked: persistent pools (tasks take 9–20 minutes instead of 25), davepl as a rival, r-01 (Rust AVX-512, +2.4% 1T on Zen 5), and the Zig first pass, whose wheel beats our ISPC wheel by 13% to 18% at 1T.
- Didn't: r-02 (new Rust toolchain, −2.2%), r-03 (alignment), hc-023 (dense pointer walk), hc-025 (NEON vector dense). hc-024 (no masks) is +1.2% on Zen 5 only; a ten-round rerun is queued.
- Found: davepl's C++ is not the top base entry. At 1T we lead it by 51% (Zen 3), 35% to 39% (Zen 5) and 28% (Cobalt); at all threads by 40% (Zen 3) and 42% (Zen 5). Rust already tops the official base table on all five runners except Threadripper 1T.
- Protocol: the first pool-scaling design (queue metric) never scaled up, and the node meter logged nothing for 40 minutes; both fixed, costs backfilled.
- Spend: about NZ$2 this run. Next: hc-026, hc-027, r-04/r-05, Zig base candidates, then the final scoreboard and README numbers.

**20:00 AEST (hour 4).**
- Worked: hc-015 (wheel sparse loop without the spill, +5% to +7% on both machines at 1T and 16T) and hc-016 (no lead-ins, +2.6% to +5%) merged. The target-specific pair (hc-019) gives Zen 5 +6.4% at 1T on top.
- Didn't: dense 160 (hc-017), base sparse ×2 (hc-018), a faster pattern build (local only, worse). Base now matches Rust phase for phase on Zen 5; the easy base levers are spent.
- Protocol: followed. I counted active pools, not deleting ones, against the limit of four; a deleting pool still bills for a minute or two.
- Spend: NZ$3.29.
- Next: the final scoreboard (both entries; Zen 3, Zen 4 with AVX-512, Zen 5, Cobalt 100) against the start of the run, then the morning report. Stopping before the time box: the remaining backlog items are each a day of work (autotune, arithmetic masks) or need Chris's call.

**19:00 AEST (hour 3).**
- Worked: hc-006 (wheel 64-bit addressing) merged after a clean Zen 3 rerun. hc-010 showed the base entry now level with Rust on Zen 5, phase for phase.
- Didn't: hc-008 (tile memcpy) flat, hc-009 (base word scan) slightly negative, hc-011 (G=6) and hc-012 (64-bit sparse indices) each lost on one machine and thread count. Both point to target-specific or register-pressure fixes (hc-014, hc-015), which are running.
- Protocol: followed. Two changes (hc-007, hc-014) only touch one instruction set, so they can't meet the "2% on Zen 3 and Zen 5" rule; they go to Chris rather than being forced through.
- Spend: NZ$2.13.
- Next: hc-013 to hc-015, then a final scoreboard run from about 21:30 AEST, leaving time for the report.

**18:05 AEST (hour 2).**
- Worked: hc-002 confirmed on fresh nodes (+22% to +24% at 1T on Zen 3 and Zen 5) and merged; hc-004 (wheel, lone prime 13) gained 4.9% to 8.7% and merged.
- Didn't: hc-005 (wheel unmasked stores) lost 1.7% on Zen 5; hc-006 hit a noisy Zen 3 node (control swung 36k–59k) and is being rerun.
- Protocol: one slip caught and fixed. A run started 17 seconds after a merge would have compared against the wrong champion; I stopped it before any round, and runs now pin `BASE` to a commit.
- Spend: NZ$1.10. The four-pool limit binds, not money.
- Next: finish hc-006b, hc-007 and hc-008 (wheel), then hc-009 (base scan) and a Zen 5 re-profile of the base champion. About two hours before the stop, a final scoreboard run of both champions against their rivals.

**17:05 AEST (hour 1).**
- Worked: the profile (hc-001) pinned 60–70% of the base gap on the dense phase; hc-002 (vector dense) gained 23% at 1T and hc-003 (sparse pointer walk) 12% on Zen 5.
- Didn't: a higher dense limit with vector resets; ISPC compile time explodes past factor 128 (over 7 minutes for one target), so it's parked.
- Protocol: followed, with one gap: `D16as_v5` gave Zen 4 twice, so hc-002 and hc-003 have no Zen 3 data. `D16a_v4` gives a 7763 and is now the Zen 3 size.
- Spend: NZ$0.54 so far.
- Next: confirm hc-002 on fresh nodes (gain above 20%), then the wheel (hc-005 running, hc-004 queued). That's the best use of the time: wheel is objective 2 and base has closed most of its gap.

## Where the cycles go

**Update, 2026-10-10 (12:10–12:25 AEST): the base against Rust, same node.** TSC cycles a pass at
1T from `hc/diag-base-phases` and `hc/diag-rust-phases` (raw output in `results/hc/diag-base-phases/`):

| Phase | Zen 5 ours | Zen 5 Rust | Zen 3 ours | Zen 3 Rust |
|---|---|---|---|---|
| sparse (factors 128 and up) | 61.1k | 61.5k | 149.0k | 147.4k |
| dense (factors below 128) | 35.7k | 35.9k | 66.9k | 82.0k |
| next-prime scan | 4.0k | 4.2k | 5.7k | 5.7k |
| set-up and destroy | 0.1k | 0.9k | 0.1k | 1.8k |
| whole pass | 100.7k | 101.7k | 221.5k | 235.1k |

On Zen 5 the two are level phase for phase. Sparse marking is 61% of a pass and already runs near
two single-byte read-modify-writes per core cycle, about the store ports' limit.

**Update, 2026-10-10 (07:30–07:35 AEST): the wheel against the Zig wheel, same node.** TSC
cycles a pass at 1T, from the diagnostic branches `hc/diag-wheel-phases` and
`hc/diag-zig-wheel-phases` (raw output in `results/hc/diag-phases/same-node/`):

| Phase | Zen 3 ISPC | Zen 3 Zig | Zen 5 ISPC | Zen 5 Zig |
|---|---|---|---|---|
| tile (7, 11) | 3.8k | 2.5k | 1.3k | 1.3k |
| 13 | 2.4k | 2.0k | 1.5k | 1.2k |
| fused groups (17–251) | 59.6k | 50.4k | 32.7k | 31.9k |
| sparse (257–997) | 54.7k | 46.5k | 29.9k | 24.0k |
| candidate scan | 4.3k | 4.3k | 2.9k | 2.9k |
| whole pass | 124.8k | 105.7k | 68.4k | 61.3k |

The Zig wheel's lead sits in sparse marking on Zen 5 and in both big phases on Zen 3. The
loops look alike in the assembly; hc-042 and hc-043 test the two differences that remain.

**Update, hc-010 (18:13–18:24 AEST, Zen 5, current champions).** The base entry now matches
Rust phase for phase: dense 38k, sparse 61k and scan 4k cycles a pass in both TSC builds
(120.1k against 119.3k passes). Without timers it runs 123k–125k passes at 1T against Rust's
125k. The wheel's largest phase is now the sparse loop at 52% of perf samples, then the fused
groups at 35% and the tile plus 13 at 12%.

### hc-001 (16:15–16:28 AEST)

Measured on Batch Spot nodes at 1T. Raw output in `results/hc/001-profile/`.

- Machines. `D16as_v5` came up as an EPYC 9V74 (Zen 4) with AVX-512 hidden, not the usual
  7763 (Zen 3). `D16as_v7` was an EPYC 9V45 (Zen 5). The v5 size no longer pins Zen 3.
- Counters. Neither size exposes hardware PMU counters: `cycles`, `instructions`, branch and
  L1 events all read "not supported". perf fell back to `cpu-clock` sampling. For the phase
  split I used TSC timers built into copies of our base entry and the Rust entry
  (`prototypes/profile/`); three rounds agreed within 0.1% on both machines.

Base entry against mike-barber's Rust, cycles per pass (TSC at 2.6GHz):

| phase | Zen 4 ours | Zen 4 Rust | Zen 5 ours | Zen 5 Rust |
|---|---|---|---|---|
| dense (factors < 128) | 114k (42%) | 79k (36%) | 69k (44%) | 40k (37%) |
| sparse | 143k (53%) | 135k (62%) | 79k (51%) | 64k (59%) |
| next-prime scan | 5k (2%) | 6k (3%) | 4k (2%) | 4k (4%) |
| set-up and allocation | 2k (1%) | n/a | 1k (1%) | n/a |
| total | 270k | 219k | 157k | 108k |

- The gap is 51k cycles a pass on Zen 4 and 49k on Zen 5. Dense accounts for 35k and 29k of it,
  sparse for 8k and 15k. The scan and set-up don't matter.
- Rust's dense phase costs a flat 2.7k cycles per factor, whatever the factor. Its macro writes
  a load, the single-bit ORs and a store for every word of a chunk, in order, and LLVM's SLP
  vectoriser turns that into AVX2 ORs with constant masks. ISPC's pipeline doesn't run SLP, so
  ours stays scalar: 4.5k to 5.6k cycles per factor below 70 on the local Xeon.
- Wheel (perf `cpu-clock`, Zen 5): the fused pattern groups (`apply_group`) take 46%, the
  sparse loop inlined in `run_sieve` 42%, the 7·11 tile (`dense_primes`) 12%. Zen 4 is the same
  shape: 43%, 41%, 12%.
- C5 ships stripped binaries, so perf shows addresses only; its hottest address takes 5.7%. The
  Rust profile under perf is unreliable (the chrooted run used 0.1 CPUs); the TSC build stands.
- Backlog consequence: dense vectorisation first (hc-002), then the sparse loop on Zen 5, then
  a higher dense limit once dense resets are cheap.

## Wheel target matrix (NEXT-STEPS task 1)

Passes in 5 s, 16-vCPU Batch Spot nodes (8 cores plus SMT), three interleaved rounds per
machine, median shown. Zen 3 and Zen 4 rounds sat within 1% of each other. On Zen 5, round 1
ran about 16% slow for every wheel variant while C5 and the base entry held steady, so the
median discards it.

| 1T / 16T | Zen 3 (EPYC 7763) | Zen 4 (EPYC 9V74) | Zen 5 (EPYC 9V45) |
|---|---|---|---|
| `avx2-i32x8` (old default) | 72.2k / 612k | 84.2k / 721k | 126.2k / 975k |
| `avx2-i32x16` | 81.5k / 705k | 97.4k / 834k | 147.0k / 1.17M |
| `avx512skx-x8` | n/a | 92.0k / 749k | 138.2k / 1.05M |
| `avx512skx-x16` | n/a | 99.8k / 841k | 150.9k / 1.25M |
| default (dispatch) | 80.2k / 704k | 99.0k / 841k | 139.8k / 1.24M |
| C5 (rogiervandam) | 65.2k / 532k | 97.0k / 770k | 139.8k / 1.20M |

- Gang width. `avx2-i32x16` beats `avx2-i32x8` on every machine, at both thread counts:
  - Zen 3: 13% at 1T, 15% at 16T
  - Zen 4: 16% at 1T, 16% at 16T
  - Zen 5: 17% at 1T, 20% at 16T

  The README figures of 11% (Zen 3) and 14% (Zen 5) understate the gain; use these numbers.
- AVX-512 stays. `avx512skx-x16` beats `avx2-i32x16` by 2% at 1T on Zen 4 and Zen 5, and at
  16T by 1% on Zen 4 and 6% on Zen 5.
- Runner 74 risk (AVX2 only, unknown host). With `avx2-i32x16`, the wheel now beats C5 at 1T on
  all three Zen generations: by 25%, 0.4% and 5%. At 16T it leads by 32% on Zen 3 and 8% on
  Zen 4, and trails by 2% on Zen 5. It trailed by 18% with `avx2-i32x8`.
- Dense threshold, re-swept with the new defaults (one run each, 1T / 16T):

  | `PRIMES_DENSE_MAX` | Zen 3 | Zen 4 | Zen 5 |
  |---|---|---|---|
  | 192 | 81.3k / 691k | 99.0k / 817k | 146.8k / 1.24M |
  | 256 | 78.5k / 704k | 97.8k / 833k | 149.6k / 1.24M |
  | 320 | 76.4k / 667k | 93.2k / 812k | 141.5k / 1.15M |

  192 ties 256 at 1T and loses at 16T, so 256 stays.

### arm64 (4 vCPU), three rounds, median

| 1T / 4T | Ampere Altra (Neoverse-N1) | Cobalt 100 (Neoverse-N2) |
|---|---|---|
| wheel `neon-i32x4` (current default) | 39.1k / 156k | 54.9k / 219k |
| wheel `neon-i32x8` | 40.8k / 163k | 63.2k / 253k |

I'll commit the `neon-i32x8` default for arm64 to `ispc-dev` next. The self-tests already pass
on both machines with that build.

## Base entry (NEXT-STEPS task 2)

Three rounds, median, 1T / all threads.

| | Zen 3 | Zen 4 | Zen 5 | Ampere (4T) | Cobalt 100 (4T) |
|---|---|---|---|---|---|
| `cauldnz-ispc-base` | 44.7k / 341k | 63.7k / 497k | 87.5k / 690k | 35.2k / 139k | 41.0k / 163k |
| mike-barber Rust extreme-hybrid | 52.4k / 411k | 76.6k / 608k | 126.6k / 877k | 36.8k / 147k | 42.9k / 171k |
| GordonBGood Chapel extreme_hybrid (4T) | 47.4k / 192k | 68.5k / 282k | 114.4k / 438k | n/a | n/a |

- The AVX-512 penalty doesn't hold on AMD. Builds with and without `avx512skx-x16` measured
  identical on Zen 4 (63.7k both) and Zen 5 (87.5k both). The 18% sandbox penalty looks like an
  Intel effect; excluding AVX-512 does no harm, so I'd keep the default as it is.
- Gap to Rust at 1T: 15% on Zen 3, 17% on Zen 4, 31% on Zen 5, and 4% to 5% on arm64. The gap
  widens on Zen 5, which suggests the Rust code uses Zen 5's wider core better. I haven't tested
  that.

## Zen 5 drift (HILL-CLIMB backlog item 1)

Same-round A/B on two separate D16as_v7 Spot nodes: old = `83c20ec`, new = the 15:00 working
tree, which includes `0b702ef` and `0a4e409`. Three rounds, median.

| 1T / 16T | node A | node B |
|---|---|---|
| new (default targets) | 147.2k / 1.23M | 143.5k / 1.21M |
| old (`83c20ec`) | 147.6k / 1.23M | 142.5k / 1.22M |
| new, forced `avx2-i32x8` | 127.9k / 970k | 121.0k / 969k |
| C5 | 133.4k / 1.25M | 130.7k / 1.15M |

- Old and new agree within 1% on both nodes, so there's no regression.
- Node B ran about 3% slower than node A, for every build.
- C5 itself measured 139.8k in the matrix run and 133.4k and 130.7k here. Cross-run comparisons
  are therefore meaningless on Zen 5; only same-round ratios count. That matches the
  `HILL-CLIMB.md` evaluation rule.
- Open question: what is the first-round slow mode? It hit only the wheel builds, only once, on
  one node. That matters for the leaderboard, because the official runners make one run.
  Hypothesis: the per-pass `aligned_alloc`/`free` of about 105KB interacting with page faults or
  transparent huge pages (C5 uses mimalloc). I'd add this to the HILL-CLIMB backlog.

## Proposed additions to the HILL-CLIMB evaluation protocol

All four target noise sources we saw today:

1. Discard one warm-up round before the scored rounds.
2. Randomise the order of builds within each round.
3. Run an A/A pair, the champion built twice under two tags, so each run measures its own noise floor.
4. Add `ispc-dev/analyze.py`, which parses the logs and reports the median, the range,
   per-round ratios to the champion and to C5, and a keep / revert / rerun verdict under the
   acceptance rule.

## Capabilities

- **Azure Batch Spot, the default for benchmarks.**
  - Command: `MODE=batch SUITE=default|targets ./azure-epyc-bench.sh <size...>`.
  - Account `batchllmwestus2gves` has 128 Spot vCPUs.
  - Nodes allocate in about 40 s and tasks start about 90 s after submission.
  - Sizes proven to work:
    - D16as_v5 (Zen 3), D16as_v6 (Zen 4), D16as_v7 (Zen 5)
    - D4ps_v5 (Ampere), D4ps_v6 (Cobalt 100)
  - Batch also lists D32–D96 as v5, v6 and v7, all untested.
  - Cost guards:
    - Each pool's autoscale formula drops to 0 nodes after `MAX_MINUTES`, even if the script dies.
    - The job terminates when its task completes, and the task has a wall-clock limit.
    - The pool, job and uploaded blob are deleted on exit.
- **Plain VMs** (`MODE=vm`), regular priority only, since this subscription offer can't use
  Spot VMs. 20 vCPU per region.
- **Local Podman** (AVX2): free builds and self-tests. Timings are noise.
- **Git:** a standing OK to push results to `ispc-dev`. The `ispc` branch and the PR need Chris's OK.
- About NZ$248 of Azure credit remains. Today's runs cost a few dollars.

## Gotchas

- Build PrimeC/solution_5 with BuildKit. The legacy builder makes it compile nothing and still
  exit 0.
- Windows checkouts are CRLF; the script ships LF copies.
- Run the bench script from a copy. Bash reads scripts as it goes, so editing one mid-run can
  break it.
- `az batch task file download` won't overwrite an existing file. The script downloads to a temp
  file and moves it.
- With `BASE=HEAD`, "old" equals "new" once a change is committed. Set `BASE` to the commit before
  the change.

## Next

1. Commit the `neon-i32x8` arm64 default and push.
2. NEXT-STEPS task 3: the README Output sections and portability paragraph, using the numbers
   above. Do you want five-round medians first? The protocol asks for five; this matrix has three.
3. Chris has asked for a Claude Code cloud session to run HILL-CLIMB unattended for a few hours.
   I'm setting that up with him now. Expect a `ispc-dev/CLOUD-RUNBOOK.md`.
