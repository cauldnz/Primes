# F2 (sparse factors in 16 KB blocks) on the submitted base entry

Grey tier, measurement for the upstream issue draft (`drafts/upstream-issue-F1-F2.md`). Never
merged anywhere.

- Candidate: `hc/f2-on-submitted` (9faa02e) = `PrimeISPC/solution_2` from `hc/ispc-landing-4`
  (d2ef0d6) plus the F2 commits 7c22f10 (block loop) and 23487a8 (16 KB default), and a one-line
  comment fix (the header said 32 KB). Conflicts with the submitted build resolved by keeping its
  16-lane AVX-512 dense path, its header and its main() set-up, and adding F2's block loop and
  `PRIMES_BLOCK_KB`. F1 is not in it. `PRIMES_TEST=1` passes (13 of 13, locally and on both nodes).
- Champion: `PrimeISPC/solution_2` at d2ef0d6. Controls: mike-barber's Rust (ctrl), davepl
  (ctrl2). `hc-pool.sh` kind `base`, 7 counted rounds after a warm-up, 2026-10-12.
- CPU model lines checked: Zen 5 = AMD EPYC 9V45 (`D16as_v7`), Zen 3 = AMD EPYC 7763 (`D16a_v4`).

Candidate over champion, per-round paired ratio, mean ± 95% interval (7 rounds):

| threads | Zen 5 | Zen 3 |
|---|---|---|
| 1 | +10.8% ± 0.2 (154.1k vs 139.2k) | +10.6% ± 1.3 (66.2k vs 58.9k) |
| 4 | +10.6% ± 0.3 | +10.3% ± 2.4 |
| 8 | +11.7% ± 0.5 | +10.1% ± 0.7 |
| 16 (all threads) | +21.8% ± 0.8 | +18.5% ± 0.5 |

A/A spread (champion against itself): Zen 5 −1.6% to +0.2% at 1T, Zen 3 −1.3% to +5.0% at 1T.
Locally (shared Xeon container) the candidate was 21% to 39% faster at 1T in two runs.
