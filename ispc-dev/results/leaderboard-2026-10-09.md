# Official leaderboard snapshot, 2026-10-09

Source: the benchmark API behind PrimeView, `https://primes.marghidanu.com/v1/`
(`/runners`, `/runners/{id}`, `/sessions?limit=20`, `/sessions/{id}/results`).
Sessions used: 9741 (EPYC VM, 2026-10-08) and 9742 (Threadripper, 2026-10-08).

Caveat: the results responses were truncated when fetched, so a few entries may be missing
from the tables below. Re-pull the full JSON before drawing fine conclusions.

## Daily runners (active in the last week)

| Runner id | Owner | CPU | SIMD | Notes |
|---|---|---|---|---|
| 73 | davepl | Threadripper PRO 9995WX, 96C/192T (Zen 5) | AVX-512, full width | Bare metal; 48 KB L1d/core; Ubuntu 24.04 |
| 74 | davepl | "EPYC Processor", 128 vCPUs | AVX2 only | QEMU VM, generic EPYC CPU model (family 23 model 1); host generation unknown; 32 KB L1d/core; no avx512f in flags |
| 18 | rbergen | Core i7-9750H (Coffee Lake) | AVX2 | |
| 24 | rbergen | Celeron 3865U | SSE4.2 only (no AVX) | |
| 36 | rbergen | Raspberry Pi 4 (BCM2711) | ARM64 NEON | ~350 results vs ~455 on x86, so arch-limited solutions are skipped |

No high-end Intel and no Intel with AVX-512 runs regularly.

## Faithful, 1-bit leaders (passes in 5 s)

| Entry | Algorithm | TR 9995WX 1T | EPYC VM 1T | Multi-thread |
|---|---|---|---|---|
| GordonBGood_extreme_hybrid (PrimeChapel/solution_1) | base | 117,862 | 52,120 | 481,106 @4 (TR), 236,444 @4 (EPYC); only reports 4 threads |
| rogiervandam_extend (PrimeC/solution_5) | other | 110,592 | 75,414 | TR: 2.33M @24, 4.34M @48, 6.98M @96, 7.59M @192. EPYC: 1.20M @16, 2.40M @32, **4.03M @64**, 3.79M @128 |
| GordonBGood_extreme-hybrid (PrimeNim/solution_3) | base | 106,968 | | |
| GordonBGood_extreme-hybrid (PrimeHaskell/solution_2) | base | 105,845 | 51,610 | 418,588 @4 (TR) |
| GordonBGood_extremehybrid (PrimeJulia/solution_4) | base | 84,564 | 41,295 | |
| serg-gini_bit-unrolled-hybrid (PrimeD/solution_3) | base | 69,449 | 30,476 | 525,425 @8 (TR) |
| fvbakel_Cwords (PrimeC/solution_3) | other | 64,531 | 32,557 | |
| danielspaangberg_5760of30030_owrb (PrimeC/solution_2) | wheel | 60,862 | 37,019 | 4.28M @192 (TR, epar) |
| mckoss-c830 (PrimeC/solution_1) | wheel | 58,536 | 25,979 | |
| ssovest-go-other-u64 (PrimeGo/solution_2) | other | 55,193 | 31,431 | |
| BlackMark-5760of30030 (PrimeCPP/solution_4) | wheel | 54,891 | 24,504 | |

Unfaithful entries (compile-time or pregenerated sieves: flo80 constexpr, BlackMark
pregenerated, mayerrobert-cl-hashdot, BradleyChatha "Cheatiness") report 10^5 to 10^9
passes and are not comparable.

## Where cauldnz-ispc might slot (estimates, not measurements)

Sandbox Xeon ratio: ISPC ≈ 1.1 × rogiervandam_extend (single-thread, interleaved runs).

- TR 9995WX, 1T: ~120–125k if the ratio holds, i.e. tied with or just ahead of the Chapel
  entry for #1 faithful 1-bit. Best-case machine: full AVX-512 and the 33 KB sieve fits L1.
- EPYC VM, 1T: ~65–85k. Runs the AVX2 path, never benchmarked in final form, with a sieve
  slightly larger than the 32 KB L1.
- Multi-thread: competitive with rogiervandam if per-core speed holds.
- Wheel category: roughly 1.5–2× the current leader (Spångberg) on both machines.

## Action items from this snapshot

1. **Benchmark the AVX2 path** (`--target=avx2-i32x8` only) on Zen. That is what runner 74
   executes. Dasv5 (Zen 3) is the closest Azure match; there's no way to reproduce QEMU's
   generic EPYC model exactly, but disabling AVX-512 is the important part.
2. **Report several thread counts**, like rogiervandam: on runner 74 his 64-thread run beats
   his 128-thread run (SMT siblings sharing a 32 KB L1). Emit lines for all hardware threads
   plus half and quarter, or physical cores; each line is a separate result.
3. **Keep ARM64 working.** The Pi 4 runs daily. Verify the NEON build and that Ubuntu 24.04
   packages `ispc` for arm64; an `arch-amd64` flag file would forfeit that runner.
4. **Check the SSE4 path** on a CPU without AVX (or force `--target=sse4-i32x4`) for the
   Celeron runner.
5. **Benchmark against GordonBGood's Chapel entry too**, not just rogiervandam. It leads
   single-thread on Zen 5. Note it only reports a 4-thread multi-threaded result.
6. **Fit the working set in 32 KB** if the EPYC numbers show an L1 penalty: shrink the
   pattern scratch, or check whether the per-pass `Group` (~70 KB, mostly unused buffers) is
   hurting via cache pollution.
