# Idea queue for the climber (workshop research, 2026-10-10 17:00)

Ranked candidates from reading the top base and wheel entries against our profile. Each still
needs its phase, its share at stake and a written prediction before it runs (AUTOPILOT.md 3).
Rules column: base = allowed for algorithm=base,faithful=yes; grey = ask Chris first.

## Multi-thread (where the official ranking is decided: 128-192 threads)
1. **Thread count from `sched_getaffinity`/`CPU_COUNT`, not `get_nprocs`.** A runner limited with
   `--cpuset-cpus` would oversubscribe us at "all threads". Correctness fix; rules: yes; do first.
2. **Pinning** at threads = vCPUs (thread i to allowed CPU i); for the half line, one thread per
   physical core (`thread_siblings_list`). 0-3% on half/quarter lines; test at 128.
3. **Why Rust falls off at full occupancy.** Page faults don't explain it (sandbox count: neither
   faults per pass). Candidates: code footprint under SMT (see 5), power limits, scheduler.
4. **Stop flag instead of a clock read per pass** (davepl C++). Only if the clocksource isn't
   vDSO. 0-1%.

## Base, dense (small factors)
5. **Code size.** Our avx2 `clear_factor` is 422 KB (72k instructions); Rust's 64 dense functions
   total 89 KB. hc-031 (dense to 191) lost 7%, consistent with instruction-cache pressure, worst
   when two SMT threads share a core. Measure everything here at threads = vCPUs, not only 1T.
6. **`avx2-i64x4` / `avx512skx-x4` targets:** one 64-bit word per lane; `clear_factor` drops to
   295 KB, masks still fold, self-test passes. 0-4%, mostly at full occupancy. Low risk.
7. **Composite factors' cases (9, 15, 21, ...) into a cold function:** hot code contiguous,
   ~76 KB executed per pass. 0-2%.
8. **Direct dense dispatch** (`if(!bit) clear<3>; ...` to 127) instead of scan plus switch. 0.5-2%.
9. **Lower dense limit for the all-threads run only** (96 or 112), if 5-7 show footprint matters.

## Base, sparse (large factors): at the rules' floor
10. **Block the sieve into L1-sized pieces**, every prime per block (rogiervandam's merged
    `sieve_base.c` is tagged base). Rules: **grey**; GordonBGood says maintainers refused
    segmentation. +5-15% at full occupancy. Do not build without Chris's OK.
11. Start at p²'s byte, not its chunk (Swift). ~0.2%.

## Wheel
12. **Fold 13 into the 7x11 tile copy** (`dst = tile[k] | pat13[r]`): one fewer sweep over 33 KB.
    +2-4%.
13. **Build the tile straight into the first dense group:** 7-47 in one sweep. +2-5%, medium risk.
14. **4K aliasing** between pattern rows and planes (separate `aligned_alloc` blocks). One
    allocation, rows offset by 64 bytes plus an odd number of lines; the Zig port's arena lays them
    out differently. 0-5%: a candidate for the remaining Zig gap.
15. Byte sparse kernel with constant masks by (p mod 8, start mod 8) for p < 500 (GordonBGood).
    Lost 9% on Xeon; never run on Zen 5. Risky.
16. Step candidates by wheel increments instead of `c += 2` plus a plane check. ~0.5%.
17. Mod-210 wheel (danielspaangberg's 48of210): large change; unknown.

## Build and environment
18. Re-test hc-013 (AVX-512 base) at full occupancy: wide vectors cost power.
19. Never move to musl/Alpine malloc without mimalloc (Zig port lost 20% at 1T).

## For the ports
- Rust: const-generic dense resetters writing 4-word vectors explicitly (LLVM's SLP leaves P 85-129
  scalar); pointer-walk sparse loop; `std::thread::scope`; `num_cpus`.
- C++: `template<int P>` always-inline resetters, `__restrict`, `-O3 -march=native`,
  `posix_memalign`, `sched_getaffinity` for the thread count.
- Zig: planes and pattern rows in one arena block (see 14); `@Vector(4,u64)` with comptime P.

Source code read: PrimeRust/solution_1, PrimeChapel/solution_1, PrimeNim/solution_3,
PrimeHaskell/solution_2, PrimeJulia/solution_4, PrimeSwift/solution_1, PrimeCPP/solution_5,
PrimeC/solution_2 and solution_5, PrimeZig/solution_3 and solution_4.
