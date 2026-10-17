# Run 11 final scoreboard (Fai)

The candidate is the final champion `hc/fai-champion` e80bf39 (fai-011). The "champion" label
in these logs is the Phase 0 baseline 1ce921d, so each round gives before and after. The
controls are plain OCaml (`hc/ocaml-final`, solution_4), mike-barber's Rust and our ISPC base
(`hc/ispc-landing-4`, solution_2). All of them ran in the same 6 counted rounds on each
machine, 17 October 2026, 02:45-03:00 UTC. The CPU model line was checked in every log.

## Passes in 5 s (median of 6 rounds)

| | Zen 5 1T | Zen 5 4T | Zen 3 1T | Zen 3 4T | Cobalt 1T | Cobalt 4T |
|---|---:|---:|---:|---:|---:|---:|
| Fai, final (e80bf39) | 10.2k | 12.9k | 6.0k | 6.3k | 6.2k | 8.2k |
| Fai, Phase 0 baseline (1ce921d) | 2.0k | 7.4k | 0.9k | 3.6k | 1.2k | 4.7k |
| plain OCaml (solution_4) | 32.9k | 120.6k | 17.2k | 65.9k | 3.4k | 13.0k |
| mike-barber Rust | 126.2k | 469.9k | 53.5k | 211.0k | 42.9k | 171.4k |
| our ISPC base | 139.0k | 517.7k | 56.8k | 224.4k | 42.0k | 168.1k |

Zen 5 is an AMD EPYC 9V45 (D16as_v7), Zen 3 an AMD EPYC 7763 (D16a_v4) and Cobalt 100 an Arm
Neoverse N2 (D4ps_v6, where 4T is all threads).

## Per thread, the leaderboard's sort key (passes per second per thread)

| | Zen 5 1T | Zen 5 4T | Zen 3 1T | Zen 3 4T | Cobalt 1T | Cobalt 4T |
|---|---:|---:|---:|---:|---:|---:|
| Fai, final | 2,046 | 647 | 1,197 | 314 | 1,243 | 409 |
| Fai, baseline | 393 | 369 | 184 | 181 | 233 | 233 |
| plain OCaml | 6,571 | 6,022 | 3,441 | 3,292 | 682 | 649 |

## Against the baseline and against OCaml

The final champion against the Phase 0 baseline, paired by round:

| | Zen 5 | Zen 3 | Cobalt |
|---|---|---|---|
| 1T | +420.5% ± 1.4 | +552.9% ± 5.5 | +433.0% ± 0.2 |
| 4T | +75.3% ± 1.3 | +73.0% ± 0.9 | +75.3% ± 0.1 |

Against plain OCaml with the same design:

| | Zen 5 | Zen 3 | Cobalt |
|---|---|---|---|
| 1T | 0.31 times | 0.35 times | 1.82 times |
| 4T per thread | 0.11 times | 0.10 times | 0.63 times |

The 4T gap comes from Fai's whole-program concurrent mode. With `Concurrency` in `main`,
every array access is a runtime call (fai-005, fai-007).
