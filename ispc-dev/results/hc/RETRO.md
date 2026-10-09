# Run retrospectives (newest first)

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
