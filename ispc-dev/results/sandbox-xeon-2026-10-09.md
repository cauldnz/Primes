# Sandbox results, 2026-10-09

Machine: Intel Xeon @ 2.80 GHz, 2 vCPUs, shared cloud sandbox (noisy: expect ±5–10% run to run).
Compilers: gcc 13.3, clang 18, rustc stable, ISPC 1.27.0 (dev) and 1.22.0 (Ubuntu package).
All entries built natively with their own Dockerfile flags (Docker Hub was unreachable).

## Leaders (passes in 5 s)

| Entry | Tags | 1 thread | 2 threads |
|---|---|---|---|
| rogiervandam_extend (PrimeC/solution_5) | other, faithful, 1 bit | 48,416–55,601 | 101,811 |
| danielspaangberg_5760of30030 (PrimeC/solution_2) | wheel, faithful, 1 bit | 19,720 | 48,105 |
| mike-barber_bit-extreme-hybrid (PrimeRust/solution_1) | base, faithful, 1 bit | 32,514 | 65,282 |
| fvbakel / davepl / others | | < 25,000 | |

The `constexpr` entries (PrimeCPP/solution_3, PrimeRust/solution_6) compute the sieve at compile
time and report millions of passes; they are unfaithful and not comparable.

## ISPC progression (1 thread, AVX-512 unless noted)

| Version | Passes | Change |
|---|---|---|
| Scalar C reference (prototypes/base.c) | 6,726 | naive 1-bit odds-only |
| sieve.ispc, naive SIMD | 6,297 | per-lane integer divide per word |
| sieve.ispc, per-prime patterns, AVX2 | 10,557 | |
| sieve.ispc, per-prime patterns | 13,738 | pattern tiling, gather per lane |
| sieve2.ispc, contiguous pattern loads | 8,475 | regression: `while (r >= p)` became a hardware divide |
| sieve2.ispc, single conditional subtract | 29,337 | divide removed |
| sieve2.ispc, 8 primes fused per pass | 45,929 | odds-only sieve is 62 KB, L2-bound |
| sieve3.ispc, mod-30 wheel, 8 planes | 38,120 | regression: pattern rebuilt per plane |
| sieve3.ispc, one pattern per prime + rotation | 50,647 | |
| sieve3.ispc, phase table, interleaved sparse | 58,755 | no divides left in dense path |
| PrimeISPC/solution_1 (faithful refactor) | 56,457–57,754 | 2 threads: 107,784–113,201 |

## Things that did not help

- Group sizes of 12 or 16 (patterns overflow L1); 4–8 is the sweet spot.
- Accumulating pattern words in a register while building patterns (slower than bit RMW).
- Manually unrolling the 8 sparse streams into scalar locals (no gain, within noise).

## Dense threshold (PRIMES_DENSE_MAX), interleaved runs

| Threshold | Passes |
|---|---|
| 256 | 60,187 / 61,001 |
| 320 | 58,143 / 58,625 |
| 384 | 59,243 / 61,092 |
| 448 | 59,440 / 62,182 |

Flat within noise between 256 and 448; 384 chosen. Re-tune on EPYC.
