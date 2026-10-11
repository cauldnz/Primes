# Draft: keep rule on the leaderboard's measure (for Chris, before the next run)

Not in force. It would replace "Acceptance rule" in `HILL-CLIMB.md` once Chris agrees.

## Why change it

The contest's report (`tools/src/formatters/table.ts` upstream) ranks two tables, one thread and
more than one, each by passes per second per thread. In the official sessions of 10 October every
faithful multi-thread leader is a 4-thread line (2-thread on the two small runners), because a
few threads on a big idle machine run at nearly one-thread speed. Both tables therefore reward
the speed of one core. Our current rule decides at one thread *or all threads*, whichever is
better, so a change that only helps with every core busy can be kept although it moves no
ranking. `tools/rank.py` reproduces the official ranking from saved session files.

## The rule

Each round gives one paired ratio per thread count, candidate over champion in the same round.

- **Deciding measure:** passes per second per thread at **1 thread** and at **4 threads** (one
  thread per core on a 16-vCPU node).
- **Keep** when, on both Zen 5 and Zen 3, the 95% interval's lower end is at least +1% at 1T or
  at 4T, and neither of the two loses 1% or more on the mean.
- **Gates** (no loss of 1% or more on the mean at 1T and 4T): Intel AVX2 for any change to x86
  code shared with the AVX2 path; Cobalt 100 for any change to code the Arm build compiles. The
  target-specific rule stays: a target whose compiled code is byte-identical needs no run.
- **Recorded, not decided:** all-threads and half-threads totals. A loss there of more than 5% is
  reported to Chris rather than reverted, since the entries print those lines too.
- **More rounds** while an interval straddles +1%, up to 20. **Revert** otherwise.
- **Machines:** check the CPU model in every log against the pool's intended chip; a run on the
  wrong chip doesn't count (backlog 33).

## What it would have changed, looking back

From the ledger: the keeps whose case rested on all-threads gains (the multi-thread work on
pinning and affinity, the 16T side of F2) would have been recorded but not decided on that
basis; fold-1pc, which loses 0.5% at 16T and gains 7% at 1T and 4T, would have been kept as it
was. Worth a full backtest over the ledger before adopting it.

## Open question for Chris

The entries print one thread, then all, half and a quarter of the hardware threads. On the
192-thread Threadripper none of those is a 4-thread line, so under this rule the measure we climb
on is one the entries don't report there. Adding a 4-thread line (`hc/line-4t`, not yet built)
closes that gap.
