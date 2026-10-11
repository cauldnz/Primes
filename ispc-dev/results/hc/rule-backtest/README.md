# Backtest of the per-thread keep rule (run ap-20261011T0645Z, phase 0 item 5)

`analyze.py` now decides by HILL-CLIMB.md's per-thread rule (1T and 4T on Zen 5 and Zen 3; Intel
AVX2 and Cobalt gate; all-threads recorded; logs on the wrong chip not counted). Run on the logs
of run ap-20261011T0100Z, old verdict against new:

| Experiment | Old rule (1T or all threads) | New rule (1T or 4T) | Changes the decision? |
|---|---|---|---|
| f4-dense-128 … 640 (5) | REVERT | REVERT | no |
| p-cpp-wheel-idea12 (6 rounds) | MORE ROUNDS | KEEP | it was kept after 12 more rounds anyway |
| p-rust-wheel-idea12 | REVERT (−1.6% at 8T) | REVERT (can't reach +1%) | no |
| p-cpp-base-f1, p-rust-base-f1 (grey) | KEEP | KEEP | no |
| p-cpp-wheel-group32 | REVERT | REVERT | no |
| p-cpp-wheel-ub | MORE ROUNDS | REVERT | kept as a correctness fix either way |
| p-cpp-wheel-clang | KEEP | KEEP | no |
| s5-starts-ef | REVERT (Cobalt −1.1%) | REVERT (Cobalt gate) | no (the x86-only variant was kept) |
| s5-tables | KEEP | KEEP | no |
| b1-sparse-last, ha-018, b2-sparse-prefetchw, p-rust-base-2 | REVERT | REVERT | no |
| **p-cpp-wheel-clang-idea12** | **KEEP** (16T) | **MORE ROUNDS** (1T/4T straddle +1%) | **yes**: it is the C++ wheel champion; more rounds this run |
| b2-base-fold-1pc, p-rust-base-noavx512 (Zen 5 only) | MORE ROUNDS | MORE ROUNDS | no: both were kept under the target-specific rule (other targets byte-identical), which analyze.py cannot see |
