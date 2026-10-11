# Run 10 final scoreboard (2026-10-12, 10:05 AEST)

Passes in 5 seconds, median of 6 counted rounds after a warm-up, every entry in the same rounds
on the same node. Raw logs beside this file. Zen 5 = EPYC 9V45 (`D16as_v7`), Zen 3 = EPYC 7763
(`D16a_v4`), Cobalt 100 = Neoverse N2 (`D4ps_v6`, 4 vCPUs, so its 4T line is all threads).

The Zen runs measured the OxCaml build at 2d1ae49; its x86 binary is the same as the final
champion 37e493e, whose last change (ox-021) touched Arm-only files. Cobalt measured 37e493e.

| | Zen 5 1T | Zen 5 4T | Zen 3 1T | Zen 3 4T | Cobalt 1T | Cobalt 4T |
|---|---:|---:|---:|---:|---:|---:|
| OxCaml base (`PrimeOCaml/solution_3`, 37e493e) | 72.2k | 261.5k | 37.2k | 137.0k | 11.8k | 41.9k |
| plain OCaml base (`PrimeOCaml/solution_4`, 0aaa340) | 32.9k | 121.0k | 18.2k | 69.0k | 3.4k | 13.1k |
| gkpotter faithful (`PrimeOCaml/solution_1`) | 1.6k | - | 0.8k | - | 0.6k | - |
| gkpotter unfaithful (`PrimeOCaml/solution_2`) | 1.7k | - | 1.0k | - | 0.6k | - |
| mike-barber Rust | 126.3k | 471.8k | 56.5k | 220.0k | 42.9k | 171.3k |
| our ISPC base (`hc/ispc-final`) | 138.9k | 518.0k | 60.0k | 233.4k | 42.1k | 168.0k |

Ratios at 1T:

| | Zen 5 | Zen 3 | Cobalt |
|---|---:|---:|---:|
| OxCaml / plain OCaml | 2.19 | 2.04 | 3.45 |
| OxCaml / ISPC base | 0.52 | 0.62 | 0.28 |
| OxCaml / Rust | 0.57 | 0.66 | 0.28 |
| OxCaml / gkpotter faithful | 44 | 47 | 19 |

Per thread, 4T keeps 91% (Zen 5), 92% (Zen 3) and 89% (Cobalt) of the OxCaml 1T rate; plain
OCaml keeps 92%, 95% and 96%.
