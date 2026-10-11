# Generalising the ISPC design to other languages

A record per language of what carried over from the ISPC entries (wheel: `PrimeISPC/solution_1`;
base: `PrimeISPC/solution_2`), kept for the write-up. Numbers are passes per second per thread at
one thread, median of 6 paired rounds, from the final scoreboard of run ap-20261011T0645Z.

## Run ap-20261011T0645Z (11 October)

| Language | Experiments decided | Kept | Gap to ISPC at 1T, Zen 5 / Zen 3 | What carried over | What did not |
|---|---|---|---|---|---|
| C++ wheel (PrimeCPP/solution_7) | 2 | 0 | −14% / +7% | the design itself; clang over GCC (run 8) | ISPC's one-base-pointer group loop (+7.7% Zen 5, −2.8% Zen 3) |
| C++ base (PrimeCPP/solution_6) | 2 (+ gate check) | 1 | 0% / −8% | the 512-bit dense routines on Zen 5 only (CPUID family 1Ah) | |
| Rust wheel (PrimeRust/solution_8) | 5 (incl. a profile) | 3 | −6% / −5% | pattern build without a bit loop; bounds checks hoisted out of the group loop (raw pointers inside) | |
| Rust base (PrimeRust/solution_9) | 1 | 0 | −11% / −14% | AVX-512 off (run 8) | dense phase with masks in registers (flat) |
| Zig base (PrimeZig/solution_4) | 3 | 1 | −9% / 0% | the pass for 3 initialises the sieve | a twice-wide dense step on Zen 5 (−8.9%: Zig 0.13 emits no 512-bit code there); the evex512 build flag (no change, unverified) |
| Zig wheel (PrimeZig/solution_4) | 3 | 3 | −5% / +4% | the 7×11 tile and 13 in one pass; comptime tables (permitted, +16%) | |

Gaps: what generalises easily is the algorithmic shape (planes, tile, groups, tables). What does
not is the code generation ISPC gets for free: Rust needed its bounds checks hoisted by hand
(170 → 93 instructions per 32 words), and the Zen 5 512-bit gains depend on each compiler emitting
512-bit code there at all (C++ yes with `-march=native`; Zig 0.13 no).

Node-minutes per language are not separable from `results/cost-log.csv`, which is kept per pool,
not per task; about 6 rounds × 2 chips per experiment throughout.
