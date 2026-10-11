# Run retrospectives (newest first)

## ap-20261011T1929Z (2026-10-12, 05:29 to 11:29 AEST): OxCaml

- Calibration: 6 of 22 predictions in range on both Zens (ox-002 on x86, ox-006, ox-008, ox-014,
  limit 96, ox-021); 5 more in range on one Zen (ocaml-004, ox-009, ox-011, ox-016, ox-017).
  Out: toolchain time (predicted 30-60 min, took 6-10), plain port (2-4x gkpotter, got 20x),
  GC (−5 to −10% 1T, got −3%), SIMD copy (+10-30%, got +41-60%), untagged (+5-15%, got +16-22%
  and −28% on Arm), Bigarray, Arm two-run, narrow sparse ORs, sparse unroll, the ox-019 merge,
  plain 32-bit stores. Upside misses were all on x86 OxCaml features; downside misses on Arm.
- Cost per kept change: 2,045 node-minutes for 7 keeps in the two champions, about 290 each
  (toolchain builds and the final scoreboard included). Lost: about 40 Cobalt node-minutes to a
  DiskFull node (the standalone Dockerfile build); no Spot pre-emptions; pools scaled to zero
  between tasks (taskcompletion), so no idle floors.
- Protocol: every candidate rebuilt and self-tested here before Azure; diffs read; five
  candidates stopped at the local gate; Cobalt run whenever the Arm binary changed, skipped only
  when byte-identical; two combinations measured before the champion moved (one kept, one
  reverted). Skipped: a profile before the first plain-OCaml experiment (ocaml-002 went first
  because it also gave the first Azure numbers); the cold read of the READMEs was done by an
  agent at the end, not before each README change.
- Next time: diagnose a platform gap with the compiled code first. Two guesses at the Arm loop
  (ox-010, the plain two-run port) cost an hour before the assembly showed the store barrier in
  minutes.

## ap-20261011T0645Z (2026-10-11, 16:45 to 22:45 AEST)

- Calibration: size cliff 4 of 6 predictions held (Zen 3 wheel drop wrong, Zen 5 base step low).
  Experiments: in range for fold Zen 5 gate (+5-8%; +6.8%), C++ base wide (+6.1%), Rust wheel
  group (+5-10% predicted, +13-17%: above), Zig wheel group (+2-5%; +1.8/+2.7%), Zig tables+group
  (+1-3%; +1.6/+5.1%); misses: Zig base wide (+2-6%; −8.9%), Zig evex512 (+3-8%; 0), C++ wheel
  r9 (+1-4%; +7.7% Zen 5 but −2.8% Zen 3), compact tables (0 to +2%; −2.4%), Rust base dense.
- Kept: hc/champion 216629d (4T line, fold gated on Zen 5); solution_3 (tables wheel) as
  hc/ispc-final-tables 57e0792; Rust wheel a8d9f07 (pattern + group: +23.6% Zen 5 at 1T over the
  run start); C++ base 558a949 (Zen 5 wide path); Zig 8ba3386 (base + wheel group) and the Zig
  tables line 138e074.
- Lost: two port submits refused (candidate equals champion) and redone against parents; tag
  pushes refused (403), final refs made as branches; one worktree path clash (no harm).
- Protocol: per-thread rule throughout; every candidate screened on AMD; fixed port shares held;
  three-hour review written on time after Chris asked about the logs (the 3h review was about to
  be late); pools taken down as their work finished. The final scoreboard was started at 10:33Z
  rather than 12:15Z, as soon as no ISPC experiment was open: it finished with time to spare.
- Next time: verify build-flag experiments inside the image (print the chosen flags); have
  hc-pool.sh accept a reference run with cand = champ for scoreboards; clear the conversation
  before a long run (cache reads per call stayed about 0.4M).

## ap-20261011T0100Z (2026-10-11, 11:00 to 15:00 AEST)

- Calibration: 6 of 19 predictions in range. Hits: F4 slope (sign known after 384, 128/192 as
  expected), Rust AVX-512 off (+1-5% predicted, +10%: above range, counted as a miss), crishoj
  under our wheel, s5 profile share (5-15% predicted, 23.5%: miss), s5-starts-ef (+3-6%; +5.5%
  Zen 5), fold-1pc (+5-8%; +7.5%), C++ IDEAS 12 (+2-6%; +6.2% Zen 5), clang C++ wheel (+5-18%;
  +16-20%). Misses: F4 (flat to +2%; −7% to −27%), wheel-210 (−5% to +3%; −40%), the Cobalt
  loop test (+1-2%; flat, −1.9% Zen 5), both prefetches, the Rust resetter, hc-018 on Zen 3,
  the tables (+5-15%; +23%), the C++ base clang (−63%).
- Kept: clean hc/champion 1551635 → 9f62bd6 (wheel start offsets, x86) → 330b3d4 (base
  fold-1pc); hc/champion-tables 90e81f9 (build-time tables); C++ wheel champion 547221c
  (alignment fix, clang, IDEAS 12); Rust base champion (AVX-512 off); grey: F1 on both base
  ports. About 1,200 task-minutes for 8 keeps: about 150 per kept change.
- Lost: two queued ISPC wheel rechecks cancelled after Chris's priority change; two Zen 4 tasks
  cancelled when the D16as_v5 node came up as a 7763; the Zig profile's first run (its phase
  lines were filtered out); the first Zen 5 submit of b1-sparse-last failed silently.
- Protocol: the event log stopped 01:11-02:26 (direct commits bypassed autolog; fixed and
  backfilled); the first two hourly reviews were missed; three local losers were dropped before
  Chris's rule (all re-screened, all worse on Zen); one commit landed on local ispc-dev before
  push and was undone; phase 1's 75 minutes overran into the base work by design after Chris's
  messages.
- What worked: profile first (stream 5 found 23.5%, both halves paid); asm identity to carry
  measurements across a guard (s5-starts-ef-x86, fold-1pc) instead of rerunning; borrowed build
  settings (clang, AVX-512 off) were the cheapest big wins in the ports.
- New harness items: tick.sh warns when EVENTS.jsonl lags status.json; hc-pool records each
  task's CPU model in jobs.tsv and refuses a size whose node is not the expected CPU (D16as_v5);
  submit fails loudly when `task create` errors (the silent Zen 5 miss).

## ap-20261010T2040Z (2026-10-11, 06:40 to 10:30 AEST)

- Calibration: 3 of 6 predictions in range. Hits: F1's sparse phase (−10% expected, −18%), F1 on
  F2 (little expected; −1 to −2%), IDEAS 12 on the new champion (+1-3%; +1.2-1.7% at all
  threads). Misses: F2 (+30% at 1T on Zen 5 expected, +9%), wheel F1 (+3-6% at all threads
  expected, −7.5%), F5 fold (expected a gain; −5% at 32T from the zmm clock).
- Kept: IDEAS 12 (clean, both lineages), F1 (grey), Zig F1 (grey, new Zig lineage). About 740
  node-minutes after removing the tally overcount, about 250 per kept change; tasks busy about
  80% (estimated from run counts). Lost: 25 minutes of the 96-vCPU node to the low-priority core
  quota (it sat at 0 nodes with a resize error until the 32-vCPU pool was deleted), and with it
  F6.
- Followed: falsify first (F1's profile before its A/B runs); arm gate before every base merge
  (it caught F2). Skipped: a phase profile for F2 (time); the Zen 4 recheck for IDEAS 12 reused
  last run's numbers (wheel-group32 does not touch the non-AVX-512 code).
- What worked: two background agents writing candidates while ticks fed five pools; the
  NEON-identical x86-only F2 (asm diff) instead of a second arm run; the porting rule turned one
  ISPC win into a second entry's win within the hour.
- What did not: a pool brought up while others held the quota; `st.py event` called with its
  arguments in the wrong order (the text went into `level`); a status.json rewrite with a
  different indent that touched every line.
- New harness items: 29 (`up` checks the low-priority core quota against the pools already
  holding nodes and says what to take down), 30 (`st.py event` checks its level argument),
  31 (record task start and end times in the output so busy share is measured, not estimated).

## ap-20261010T0715Z (2026-10-10, 17:15 to 22:30 AEST)

- Calibration: 5 of 12 predictions in range. Hits: thread-count fix level, stop flag flat, arena
  count flat, scaling repeat agreed, loaded one-thread drop matched the profile. Misses: pinning
  (expected level, lost 5% at 24T), sparse prefetch (expected +2-5% at 96T, -7% at 32T),
  avx2-i64x4 (expected a gain under SMT, flat), Rust base port (expected ahead of mike-barber,
  -12% on Zen 5), wheel-group32 on Zen 4 (expected +2-4%, 0%), IDEAS 12 on Zen 5 (+1-3%
  expected, three runs disagreed), G=8 (expected +1-3%, -2.4% at 96T).
- Kept: thread-count fix (merge pending Chris). Candidate for Chris: wheel-group32.
  Node-minutes 884, 69% in tasks (31% last run).
- What worked: queues on every node, fed from agent-written candidates verified here; the
  local gate caught nothing this time but cost little; Chris's three scaling tests turned a
  vague "full-occupancy lead" into a clear SMT and clock story; the quiet second node made the
  96-vCPU numbers quotable.
- What did not: a pool created for a VM size Batch does not offer, and four submits that then
  failed silently; a diagnostic that passed Rust the wrong flag (`-d` for `-s`); a pinning
  candidate that assumed Linux's usual SMT sibling numbering, which Azure does not use; an
  agent's local speed claims (Rust base port +5%, C++ wheel +10%) that the nodes did not bear out.
- New harness items: 25 (check VM sizes against `az batch location list-skus` before `up`, and
  make submit fail loudly), 26 (diagnostics prove their background load is running), 27 (agents'
  local speed claims are indicative only).

## ap-20261010T0140Z (2026-10-10, 11:40 to 14:30 AEST)

- Calibration: 3 of 6 predictions in range (scaling lead held; asm showed no store saving;
  final x86 numbers as expected). Misses: p4-arm-dense predicted +3-8%, got +2.5%; init3
  predicted +1-2%, got +0.5%; sse4-i32x8 predicted within 2%, got -92%.
- Kept: p4-arm-dense (+2.5% arm, x86 identical). Node-minutes: 568; tasks used 31% of them.
- What worked: profile, then asm, then candidate; background agents writing and gating
  candidates while ticks kept pools busy; verifying each agent report before acting on it.
- What did not: submitting sse4-i32x8 after a local run had already shown it 5x slower; idle
  floor nodes.
- New harness items: 22 (pool ids in jobs.tsv), 23 (large outputs in git), and: submit must
  fail loudly when no task is created.

## ap-20261009T2033Z (2026-10-10, 06:33 to 10:00 AEST)

- Calibration: 1 of 6 predictions in range. The miss that mattered went the other way:
  hc-045 was predicted at 0–2% and gained 9–10%.
- Kept: hc-045 (wheel +9–10% at 1T on Zen 3 and Zen 5). Node-minutes: 854 this run (cost log).
- Followed: profile first (same-node phase profiles before the wheel experiments). Skipped:
  the two-stage screen (backlog item 3) for lack of time.
- What worked: diffing the faster port's source line by line, after the profile had named the
  phase. Loop-shape copies (hc-042, hc-043) did not.
- Harness faults: `prun.sh`'s shared script copy killed a task (fixed); `pgrep -f` waits that
  match their own command line (again; use `wait.sh` or PIDs); the first profiles ran on
  different nodes (backlog item 9). The worker restarted once; Batch tasks survived it.
- New harness items: none beyond 9; item 3 (two-stage screen) is now the top open item.

## ap-20261009T1349Z (2026-10-09/10, 23:49 to 02:25 AEST)

- Calibration: 3 of 11 predictions in range; seven missed high, four with the wrong sign.
- Kept: hc-035. Node-minutes: about 655 for one kept change. Lost: one 10-round Zen 5 task to
  Spot preemption (rounds salvaged by hand); idle time on floor nodes was not measured.
- Skipped: the profile-first step. Review estimates went straight to node time.
- New harness items: standing phase profile, danielspaangberg wheel rival, two-stage screen
  (`HARNESS-BACKLOG.md` 1 to 3). Full review: `REVIEW-2026-10-10.md`.
