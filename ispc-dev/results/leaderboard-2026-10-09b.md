# Official leaderboard snapshot, 2026-10-09 (b)

Source: the PrimeView API, `https://primes.marghidanu.com/v1/` (`/sessions?limit=20`, then
`/sessions/{id}/results`). Pulled 2026-10-09 by research agent 2. Unlike the first snapshot,
every response came back whole: each session's result count matches its `results_count`.

Field notes, for anyone re-pulling:

- `bits` is a string (`"1"`), not a number. `faithful` is a boolean.
- `pps` is passes per second per thread (`passes / duration / threads`). The tables below rank
  by total passes per second (`passes / duration`), which is how a multi-thread result competes.
- Rankings were stable across the three latest days: the Threadripper and EPYC sessions of 6, 7
  and 8 October (9733, 9737, 9742; 9736, 9741, 9746) put every entry named here within 4% of
  its value in the tables.

## Findings

1. **mike-barber's Rust already tops the faithful 1-bit base table on every runner, bar one
   cell.** It leads 1T on the EPYC VM, i7-9750H, Celeron and Pi 4, and leads multi-thread on
   all five runners. The exception is the Threadripper at 1T, where yellowcub and fahlman's
   Swift entry (`PrimeSwift/solution_1`, `yellowcub_fahlman_striped_UInt8`) leads with 122,869
   against Rust's 118,846 (3.4% ahead) and Chapel's 117,862.
2. **davepl_array_optimized does not top the base table on these runs.** It reports one line
   only, at all hardware threads, so it never appears in a 1T ranking. In multi-thread it ranks
   fifth on the Threadripper (5.40M passes at 192 threads against Rust's 6.83M at 96, 21% behind),
   fifth on the EPYC VM (2.49M against 2.99M, 17% behind), fifth on the i7, seventh on the
   Celeron and third on the Pi 4, where it is within 0.3% of Rust. If Chris saw it on top,
   the view was probably filtered to one line per solution at a fixed thread count, or showed
   an older session. Worth checking which PrimeView filter he used.
3. **GordonBGood's best entries rank third to sixth.** Chapel is third at 1T on the Threadripper
   (0.8% behind Rust) but fifth on the EPYC VM (52.2k, 17% behind Rust). Nim is the strongest
   of his entries away from the Threadripper (third at 1T on the i7, Celeron and Pi 4). His
   multi-thread lines are 4-thread only by design, so they rank 30th or lower on the big runners.
4. **The Swift entry is Haswell-only on x86.** It doesn't appear on the Celeron (no AVX2).
5. **Zig solution_3 (ManDeJan, ityonemo, SpexGuy) has no results** in any of these sessions; only
   solution_2's two unfaithful lines appear. Its Dockerfile downloads Zig 0.8.0 from
   ziglang.org at build time.

## Where cauldnz-ispc-base would slot (estimates from Azure ratios, not measurements)

Ratios from `STATUS.md` (hc/champion against Rust, same node, five rounds): Zen 3 +5.4% / +4.0%,
Zen 4 (AVX2 only) +7.1% / +7.0%, Zen 5 −1.6% / +13.1% before hc-013 (+1.0% at 1T on Zen 5),
Cobalt 100 −4.3%.

| Runner | Rust 1T | our estimate 1T | rank at 1T | Rust best MT | our estimate MT |
|---|---|---|---|---|---|
| 73 Threadripper (Zen 5) | 118,846 | about 118k | 2nd–4th, behind Swift (122,869) | 6.83M @96 | 7.0M–7.7M if the Azure Zen 5 16T lead (+13%) carries over; it was measured with SMT, not one thread per core |
| 74 EPYC VM (AVX2) | 63,144 | 66k–68k if the host is Zen 3 or 4 | 1st | 2.99M @128 | 3.1M–3.2M |
| 18 i7-9750H | 55,007 | unknown: no Intel AVX2 data | | 267k @6 | |
| 24 Celeron (SSE4) | 20,091 | unknown: no SSE4-only data | | 40.5k @2 | |
| 36 Pi 4 | 9,674 | about 9.3k (Cobalt ratio) | 3rd–4th | 17.6k @4 | |

To take the Threadripper 1T cell, either our entry or Rust needs about +4% on Zen 5 at 1T.

## Runner 73: Threadripper PRO 9995WX (Zen 5, AVX-512), 96C/192T

Session 9742, 2026-10-08 18:42:47 UTC, 455 results (264 faithful 1-bit).


Single thread, faithful 1-bit base, ranked by total passes per second. Rows past 10 show the best line of each named entry.

| # | Entry | Label | Threads | Passes | Passes/s |
|---|---|---|---|---|---|
| 1 | PrimeSwift/solution_1 | yellowcub_fahlman_striped_UInt8 | 1 | 122,869 | 24,574 |
| 2 | PrimeRust/solution_1 | mike-barber_bit-unrolled-hybrid | 1 | 118,846 | 23,769 |
| 3 | PrimeRust/solution_1 | mike-barber_bit-extreme-hybrid | 1 | 118,574 | 23,715 |
| 4 | PrimeChapel/solution_1 | GordonBGood_extreme_hybrid | 1 | 117,862 | 23,572 |
| 5 | PrimeNim/solution_3 | GordonBGood_extreme-hybrid | 1 | 106,968 | 21,393 |
| 6 | PrimeHaskell/solution_2 | GordonBGood_extreme-hybrid | 1 | 105,845 | 21,166 |
| 7 | PrimeJulia/solution_4 | GordonBGood_extremehybrid | 1 | 84,564 | 16,913 |
| 8 | PrimeD/solution_3 | serg-gini_bit-unrolled-hybrid | 1 | 69,449 | 13,890 |
| 9 | PrimeD/solution_3 | serg-gini_bit-extreme-hybrid | 1 | 69,219 | 13,844 |
| 10 | PrimeV/solution_2 | GordonBGood_extreme-hybrid | 1 | 67,598 | 13,520 |

Multi-thread, faithful 1-bit base, ranked by total passes per second. Rows past 10 show the best line of each named entry.

| # | Entry | Label | Threads | Passes | Passes/s |
|---|---|---|---|---|---|
| 1 | PrimeRust/solution_1 | mike-barber_bit-unrolled-hybrid | 96 | 6,833,020 | 1,365,577 |
| 2 | PrimeRust/solution_1 | mike-barber_bit-extreme-hybrid | 96 | 6,829,433 | 1,364,898 |
| 3 | PrimeRust/solution_1 | mike-barber_bit-unrolled-hybrid | 192 | 6,673,481 | 1,332,889 |
| 4 | PrimeRust/solution_1 | mike-barber_bit-extreme-hybrid | 192 | 6,668,813 | 1,331,882 |
| 5 | PrimeCpp/solution_5 | davepl_array_optimized | 192 | 5,402,341 | 1,079,246 |
| 6 | PrimeAssembly/solution_4 | cwager_x64ff_mt_extreme_maskgen_onefactor | 192 | 4,528,352 | 905,308 |
| 7 | PrimeAssembly/solution_4 | cwager_x64ff_mt_extreme | 192 | 2,329,630 | 465,647 |
| 8 | PrimeMixed/solution_4 | mmcdon20_dart+c_1_bit_par | 192 | 2,149,866 | 429,928 |
| 9 | PrimeCpp/solution_4 | BlackMark-1of2-cs-hs-inv_stridedbits<u8>-gcc | 192 | 1,890,376 | 376,310 |
| 10 | PrimeMixed/solution_5 | mikaelhildenborg_cpp_inline_amd64 | 192 | 1,822,325 | 363,636 |
| 30 | PrimeChapel/solution_1 | GordonBGood_extreme_hybrid | 4 | 481,106 | 96,218 |
| 33 | PrimeNim/solution_3 | GordonBGood_extreme-hybrid | 4 | 421,411 | 84,274 |
| 34 | PrimeHaskell/solution_2 | GordonBGood_extreme-hybrid | 4 | 418,588 | 83,651 |

Context, top five faithful 1-bit at 1T across all algorithms: yellowcub_fahlman_striped_UInt8 (base) 122,869; mike-barber_bit-unrolled-hybrid (base) 118,846; mike-barber_bit-extreme-hybrid (base) 118,574; GordonBGood_extreme_hybrid (base) 117,862; rogiervandam_extend (other) 110,592.


## Runner 74: "EPYC Processor" VM (AVX2 only), 128 vCPU

Session 9746, 2026-10-09 09:45:58 UTC, 457 results (264 faithful 1-bit).


Single thread, faithful 1-bit base, ranked by total passes per second. Rows past 10 show the best line of each named entry.

| # | Entry | Label | Threads | Passes | Passes/s |
|---|---|---|---|---|---|
| 1 | PrimeRust/solution_1 | mike-barber_bit-extreme-hybrid | 1 | 63,144 | 12,629 |
| 2 | PrimeRust/solution_1 | mike-barber_bit-unrolled-hybrid | 1 | 62,724 | 12,545 |
| 3 | PrimeSwift/solution_1 | yellowcub_fahlman_striped_UInt8 | 1 | 59,829 | 11,966 |
| 4 | PrimeNim/solution_3 | GordonBGood_extreme-hybrid | 1 | 52,401 | 10,480 |
| 5 | PrimeChapel/solution_1 | GordonBGood_extreme_hybrid | 1 | 52,223 | 10,444 |
| 6 | PrimeHaskell/solution_2 | GordonBGood_extreme-hybrid | 1 | 51,426 | 10,283 |
| 7 | PrimeJulia/solution_4 | GordonBGood_extremehybrid | 1 | 41,283 | 8,256 |
| 8 | PrimeV/solution_2 | GordonBGood_extreme-hybrid | 1 | 33,739 | 6,748 |
| 9 | PrimeD/solution_3 | serg-gini_bit-extreme-hybrid | 1 | 30,768 | 6,153 |
| 10 | PrimeD/solution_3 | serg-gini_bit-unrolled-hybrid | 1 | 29,769 | 5,954 |

Multi-thread, faithful 1-bit base, ranked by total passes per second. Rows past 10 show the best line of each named entry.

| # | Entry | Label | Threads | Passes | Passes/s |
|---|---|---|---|---|---|
| 1 | PrimeRust/solution_1 | mike-barber_bit-extreme-hybrid | 128 | 2,985,129 | 595,977 |
| 2 | PrimeRust/solution_1 | mike-barber_bit-unrolled-hybrid | 128 | 2,968,443 | 592,649 |
| 3 | PrimeRust/solution_1 | mike-barber_bit-unrolled-hybrid | 64 | 2,840,670 | 567,600 |
| 4 | PrimeRust/solution_1 | mike-barber_bit-extreme-hybrid | 64 | 2,835,837 | 566,681 |
| 5 | PrimeCpp/solution_5 | davepl_array_optimized | 128 | 2,485,399 | 496,575 |
| 6 | PrimeAssembly/solution_4 | cwager_x64ff_mt_extreme_maskgen_onefactor | 128 | 1,825,483 | 364,805 |
| 7 | PrimeAssembly/solution_4 | cwager_x64ff_mt_extreme | 128 | 992,022 | 198,087 |
| 8 | PrimeMixed/solution_4 | mmcdon20_dart+c_1_bit_par | 128 | 851,307 | 170,236 |
| 9 | PrimeMixed/solution_5 | mikaelhildenborg_cpp_inline_amd64 | 128 | 811,096 | 161,747 |
| 10 | PrimeCpp/solution_4 | BlackMark-1of2-cs-hs-inv_stridedbits<u8>-gcc | 128 | 735,385 | 146,354 |
| 31 | PrimeChapel/solution_1 | GordonBGood_extreme_hybrid | 4 | 234,480 | 46,892 |
| 32 | PrimeNim/solution_3 | GordonBGood_extreme-hybrid | 4 | 199,744 | 39,945 |
| 33 | PrimeHaskell/solution_2 | GordonBGood_extreme-hybrid | 4 | 189,117 | 37,788 |

Context, top five faithful 1-bit at 1T across all algorithms: rogiervandam_extend (other) 74,471; mike-barber_bit-extreme-hybrid (base) 63,144; mike-barber_bit-unrolled-hybrid (base) 62,724; yellowcub_fahlman_striped_UInt8 (base) 59,829; GordonBGood_extreme-hybrid (base) 52,401.


## Runner 18: Core i7-9750H (Coffee Lake, AVX2), 6C/12T

Session 9744, 2026-10-09 05:04:56 UTC, 469 results (271 faithful 1-bit).


Single thread, faithful 1-bit base, ranked by total passes per second. Rows past 10 show the best line of each named entry.

| # | Entry | Label | Threads | Passes | Passes/s |
|---|---|---|---|---|---|
| 1 | PrimeRust/solution_1 | mike-barber_bit-unrolled-hybrid | 1 | 55,007 | 11,001 |
| 2 | PrimeRust/solution_1 | mike-barber_bit-extreme-hybrid | 1 | 54,919 | 10,984 |
| 3 | PrimeNim/solution_3 | GordonBGood_extreme-hybrid | 1 | 53,298 | 10,659 |
| 4 | PrimeSwift/solution_1 | yellowcub_fahlman_striped_UInt8 | 1 | 51,584 | 10,317 |
| 5 | PrimeHaskell/solution_2 | GordonBGood_extreme-hybrid | 1 | 44,745 | 8,947 |
| 6 | PrimeChapel/solution_1 | GordonBGood_extreme_hybrid | 1 | 41,765 | 8,352 |
| 7 | PrimeCrystal/solution_2 | GordonBGood_extreme-hybrid | 1 | 31,892 | 6,378 |
| 8 | PrimeJulia/solution_4 | GordonBGood_extremehybrid | 1 | 31,654 | 6,331 |
| 9 | PrimeD/solution_3 | serg-gini_bit-unrolled-hybrid | 1 | 31,296 | 6,259 |
| 10 | PrimeD/solution_3 | serg-gini_bit-extreme-hybrid | 1 | 30,936 | 6,187 |
| 11 | PrimeV/solution_2 | GordonBGood_extreme-hybrid | 1 | 30,869 | 6,174 |

Multi-thread, faithful 1-bit base, ranked by total passes per second. Rows past 10 show the best line of each named entry.

| # | Entry | Label | Threads | Passes | Passes/s |
|---|---|---|---|---|---|
| 1 | PrimeRust/solution_1 | mike-barber_bit-extreme-hybrid | 6 | 267,459 | 53,490 |
| 2 | PrimeRust/solution_1 | mike-barber_bit-unrolled-hybrid | 12 | 263,554 | 52,708 |
| 3 | PrimeRust/solution_1 | mike-barber_bit-extreme-hybrid | 12 | 258,858 | 51,768 |
| 4 | PrimeRust/solution_1 | mike-barber_bit-unrolled-hybrid | 6 | 242,947 | 48,588 |
| 5 | PrimeCpp/solution_5 | davepl_array_optimized | 12 | 208,768 | 41,732 |
| 6 | PrimeAssembly/solution_4 | cwager_x64ff_mt_extreme_maskgen_onefactor | 12 | 193,429 | 38,686 |
| 7 | PrimeRust/solution_1 | mike-barber_bit-extreme-hybrid | 4 | 191,309 | 38,261 |
| 8 | PrimeRust/solution_1 | mike-barber_bit-unrolled-hybrid | 4 | 189,456 | 37,890 |
| 9 | PrimeNim/solution_3 | GordonBGood_extreme-hybrid | 4 | 183,425 | 36,683 |
| 10 | PrimeAssembly/solution_4 | cwager_x64ff_mt_extreme | 12 | 182,137 | 36,427 |
| 11 | PrimeHaskell/solution_2 | GordonBGood_extreme-hybrid | 4 | 161,447 | 32,260 |
| 12 | PrimeChapel/solution_1 | GordonBGood_extreme_hybrid | 4 | 156,677 | 31,333 |

Context, top five faithful 1-bit at 1T across all algorithms: rogiervandam_extend (other) 75,839; mike-barber_bit-unrolled-hybrid (base) 55,007; mike-barber_bit-extreme-hybrid (base) 54,919; GordonBGood_extreme-hybrid (base) 53,298; yellowcub_fahlman_striped_UInt8 (base) 51,584.


## Runner 24: Celeron 3865U (SSE4.2), 2C/2T

Session 9743, 2026-10-09 03:25:59 UTC, 451 results (259 faithful 1-bit).


Single thread, faithful 1-bit base, ranked by total passes per second. Rows past 10 show the best line of each named entry.

| # | Entry | Label | Threads | Passes | Passes/s |
|---|---|---|---|---|---|
| 1 | PrimeRust/solution_1 | mike-barber_bit-unrolled-hybrid | 1 | 20,091 | 4,018 |
| 2 | PrimeRust/solution_1 | mike-barber_bit-extreme-hybrid | 1 | 20,086 | 4,017 |
| 3 | PrimeNim/solution_3 | GordonBGood_extreme-hybrid | 1 | 19,163 | 3,833 |
| 4 | PrimeChapel/solution_1 | GordonBGood_extreme_hybrid | 1 | 18,655 | 3,731 |
| 5 | PrimeHaskell/solution_2 | GordonBGood_extreme-hybrid | 1 | 18,086 | 3,615 |
| 6 | PrimeCrystal/solution_2 | GordonBGood_extreme-hybrid | 1 | 16,736 | 3,347 |
| 7 | PrimeJulia/solution_4 | GordonBGood_extremehybrid | 1 | 13,452 | 2,690 |
| 8 | PrimeD/solution_3 | serg-gini_bit-unrolled-hybrid | 1 | 13,430 | 2,686 |
| 9 | PrimeD/solution_3 | serg-gini_bit-extreme-hybrid | 1 | 13,342 | 2,668 |
| 10 | PrimeV/solution_2 | GordonBGood_extreme-hybrid | 1 | 13,256 | 2,651 |

Multi-thread, faithful 1-bit base, ranked by total passes per second. Rows past 10 show the best line of each named entry.

| # | Entry | Label | Threads | Passes | Passes/s |
|---|---|---|---|---|---|
| 1 | PrimeRust/solution_1 | mike-barber_bit-extreme-hybrid | 2 | 40,455 | 8,091 |
| 2 | PrimeRust/solution_1 | mike-barber_bit-unrolled-hybrid | 2 | 40,250 | 8,050 |
| 3 | PrimeChapel/solution_1 | GordonBGood_extreme_hybrid | 2 | 38,516 | 7,703 |
| 4 | PrimeNim/solution_3 | GordonBGood_extreme-hybrid | 2 | 38,259 | 7,651 |
| 5 | PrimeHaskell/solution_2 | GordonBGood_extreme-hybrid | 2 | 36,328 | 7,248 |
| 6 | PrimeAssembly/solution_4 | cwager_x64ff_mt_extreme_maskgen_onefactor | 2 | 31,898 | 6,380 |
| 7 | PrimeCpp/solution_5 | davepl_array_optimized | 2 | 31,633 | 6,324 |
| 8 | PrimeD/solution_3 | serg-gini_bit-unrolled-hybrid | 4 | 26,603 | 5,305 |
| 9 | PrimeD/solution_3 | serg-gini_bit-unrolled-hybrid | 8 | 26,559 | 5,281 |
| 10 | PrimeD/solution_3 | serg-gini_bit-extreme-hybrid | 8 | 26,471 | 5,264 |

Context, top five faithful 1-bit at 1T across all algorithms: rogiervandam_extend_epar (other) 29,230; rogiervandam_extend (other) 28,419; mike-barber_bit-unrolled-hybrid (base) 20,091; mike-barber_bit-extreme-hybrid (base) 20,086; GordonBGood_extreme-hybrid (base) 19,163.


## Runner 36: Raspberry Pi 4 (Cortex-A72, NEON), 4C

Session 9745, 2026-10-09 07:31:30 UTC, 352 results (207 faithful 1-bit).


Single thread, faithful 1-bit base, ranked by total passes per second. Rows past 10 show the best line of each named entry.

| # | Entry | Label | Threads | Passes | Passes/s |
|---|---|---|---|---|---|
| 1 | PrimeRust/solution_1 | mike-barber_bit-extreme-hybrid | 1 | 9,674 | 1,935 |
| 2 | PrimeRust/solution_1 | mike-barber_bit-unrolled-hybrid | 1 | 9,663 | 1,932 |
| 3 | PrimeNim/solution_3 | GordonBGood_extreme-hybrid | 1 | 9,183 | 1,837 |
| 4 | PrimeSwift/solution_1 | yellowcub_fahlman_striped_UInt8 | 1 | 8,355 | 1,671 |
| 5 | PrimeHaskell/solution_2 | GordonBGood_extreme-hybrid | 1 | 7,987 | 1,596 |
| 6 | PrimeChapel/solution_1 | GordonBGood_extreme_hybrid | 1 | 7,856 | 1,571 |
| 7 | PrimeV/solution_2 | GordonBGood_extreme-hybrid | 1 | 7,758 | 1,552 |
| 8 | PrimeCrystal/solution_2 | GordonBGood_extreme-hybrid | 1 | 7,245 | 1,449 |
| 9 | PrimeD/solution_3 | serg-gini_bit-unrolled-hybrid | 1 | 6,535 | 1,307 |
| 10 | PrimeD/solution_3 | serg-gini_bit-extreme-hybrid | 1 | 6,514 | 1,303 |

Multi-thread, faithful 1-bit base, ranked by total passes per second. Rows past 10 show the best line of each named entry.

| # | Entry | Label | Threads | Passes | Passes/s |
|---|---|---|---|---|---|
| 1 | PrimeRust/solution_1 | mike-barber_bit-extreme-hybrid | 4 | 17,565 | 3,512 |
| 2 | PrimeRust/solution_1 | mike-barber_bit-unrolled-hybrid | 4 | 17,542 | 3,508 |
| 3 | PrimeCpp/solution_5 | davepl_array_optimized | 4 | 17,512 | 3,494 |
| 4 | PrimeD/solution_3 | serg-gini_bit-unrolled-hybrid | 8 | 17,552 | 3,493 |
| 5 | PrimeChapel/solution_1 | GordonBGood_extreme_hybrid | 4 | 17,411 | 3,481 |
| 6 | PrimeD/solution_3 | serg-gini_bit-unrolled-hybrid | 4 | 17,394 | 3,471 |
| 7 | PrimeD/solution_3 | serg-gini_bit-extreme-hybrid | 4 | 17,161 | 3,425 |
| 8 | PrimeNim/solution_3 | GordonBGood_extreme-hybrid | 4 | 17,020 | 3,403 |
| 9 | PrimeD/solution_3 | serg-gini_bit-extreme-hybrid | 8 | 16,792 | 3,343 |
| 10 | PrimeHaskell/solution_2 | GordonBGood_extreme-hybrid | 4 | 16,150 | 3,221 |

Context, top five faithful 1-bit at 1T across all algorithms: danielspaangberg_5760of30030_owrb (wheel) 11,266; rogiervandam_extend (other) 10,992; rogiervandam_extend_epar (other) 10,991; danielspaangberg_480of2310_owrb (wheel) 10,108; mike-barber_bit-extreme-hybrid (base) 9,674.

