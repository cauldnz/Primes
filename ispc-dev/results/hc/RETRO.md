# Run retrospectives (newest first)

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
