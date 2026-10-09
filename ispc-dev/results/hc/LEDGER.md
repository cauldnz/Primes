# Hill-climbing ledger

| id | date | entry | hypothesis | prediction | Zen 3 1T/16T (median, Δ) | Zen 5 1T/16T (median, Δ) | verdict | commit |
|---|---|---|---|---|---|---|---|---|
| 001 | 2026-10-09 | both | Profile first: where do the cycles go, ours against C5 and Rust? | Base gap sits mostly in the dense phase (local Xeon: dense 128k cycles a pass against Rust's 82k) | Zen 4 (D16as_v5 landed on a 9V74): base dense 114k / sparse 143k / scan 5k cycles a pass, Rust 79k / 135k / 6k | Zen 5: see note | measurement | `3b02d14` (harness) |
| 002 | 2026-10-09 | base | Vector dense resets: one single-bit OR per composite, per SIMD lane, folded by LLVM into constant vector ORs, as the SLP vectoriser does for Rust | +10% to +18% at 1T on Zen, similar at all threads | Zen 3 (7763, confirm run): 57.2k / 416.9k, +21.9% / +21.8%, 5/5; Zen 4 (v5): +22.9% / +28.1%, 4/4 | Zen 5: 107.6k / 888.3k, +23.5% / +29.0%, 5/5; confirm run +23.8% / +29.7%, 4/4 | KEEP, confirmed on fresh nodes, merged | `4d35020` on `hc/champion` |
| 003 | 2026-10-09 | base | Pointer walk over sparse chunks: 11 instructions per eight ORs instead of 27 | Zen 5 1T +4% to +8% (sparse gap 15k cycles), Zen 4 +0% to +3% | Zen 4 (v5): 51.3k / 416.6k, +3.6% / +7.8%, 5/5, A/A ±0.5% | Zen 5: 97.8k / 696.3k, +12.3% / +1.3%, 5/5, A/A ±0.9% | KEEP, merged | `cacfd8f` on `hc/champion` |
| 004 | 2026-10-09 | wheel | A lone prime (13) skips the fused group loop | +1% to +3% 1T (13 costs ~9k cycles a pass); local Xeon +0.4% to +5.8% | pending | pending | pending | `hc/004-wheel-one-member` |
| 005 | 2026-10-09 | wheel | No masked stores: apply_group unmasked, partial vectors run into padding | +3% to +6% on the AVX2 path, +1% to +3% with AVX-512; local Xeon +2% to +19% | Zen 3 (7763): 87.3k / 732.1k, +4.5% / +4.1%, 4/5 at 1T, 5/5 at 16T; A/A at 1T −2.6% to +4.6% | Zen 5: 146.9k / 1.22M, −1.7% / −0.9%, 0/4 | REVERT (Zen 5 −1.7% at 1T) | `hc/005-wheel-unmasked-tails` |
| 006 | 2026-10-09 | wheel | Build with `--addressing=64`: ISPC sign-extends 32-bit offsets on every strided OR, and the sparse loop spills | +3% to +6% 1T on Zen (sparse is ~42% of the wheel); local Xeon +4% to +8% | pending | pending | pending | `hc/006-wheel-addr64` |

## Notes

**001, profile.** Azure D-series nodes expose no hardware PMU counters, so perf fell back to
`cpu-clock` sampling, and the phase split came from TSC timers built into copies of our base
entry and the Rust entry. Dense was 60–70% of the base gap to Rust and sparse 15–30%. Next:
vectorise dense.

**002, vector dense.** The prediction (+10% to +18%) was too cautious: +22% to +24% at 1T on
Zen 3, 4 and 5, and +22% to +30% at all threads. Over 20%, so it was confirmed on fresh nodes
with clean builds, and the rules re-read: each composite has its own single-bit OR in the
source, in the lane holding its word, and LLVM merges them, as it does for the Rust entry. The
base entry now beats Rust at 1T on Zen 3 (+3.1%) and Zen 4 (+2.4%) and trails by 15% on Zen 5.
Vector resets past factor 128 blow up ISPC compile times (over 7 minutes for one target), so
a higher dense limit is parked. `avx2-i32x16` and `avx512skx-x16` fail to fold the masks.

**003, sparse pointer walk.** Zen 5 +12.3% at 1T against a 4–8% prediction: on Zen 5 the
sparse loop was bound by instruction count, not stores. Zen 4 gained 3.6% at 1T and 7.8% at
16T. The local Xeon showed nothing, which is a warning about ranking changes there.

**005, wheel unmasked stores.** Zen 3 gained 4% to 6%; Zen 5 lost 1.7% at 1T with a noisy A/A.
On AVX-512 masked stores are cheap, so the padding and overrun only add work there. Next: keep
the change for AVX2 targets only, which can't move Zen 5. That can't pass the "both machines"
rule by construction, so it needs Chris's call if it wins on Zen 3.
