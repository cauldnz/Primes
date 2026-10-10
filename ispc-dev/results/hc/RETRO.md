# Run retrospectives (newest first)

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
