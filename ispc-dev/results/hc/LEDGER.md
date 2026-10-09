# Hill-climbing ledger

| id | date | entry | hypothesis | prediction | Zen 3 1T/16T (median, Δ) | Zen 5 1T/16T (median, Δ) | verdict | commit |
|---|---|---|---|---|---|---|---|---|
| 001 | 2026-10-09 | both | Profile first: where do the cycles go, ours against C5 and Rust? | Base gap sits mostly in the dense phase (local Xeon: dense 128k cycles a pass against Rust's 82k) | Zen 4 (D16as_v5 landed on a 9V74): base dense 114k / sparse 143k / scan 5k cycles a pass, Rust 79k / 135k / 6k | Zen 5: see note | measurement | `3b02d14` (harness) |
| 002 | 2026-10-09 | base | Vector dense resets: one single-bit OR per composite, per SIMD lane, folded by LLVM into constant vector ORs, as the SLP vectoriser does for Rust | +10% to +18% at 1T on Zen, similar at all threads; local Xeon gained 0% to 19% over four rounds | running | running | running | `164f8c1` on `hc/002-vec-dense` |
| 003 | 2026-10-09 | base | Pointer walk over sparse chunks: 11 instructions per eight ORs instead of 27 | Zen 5 1T +4% to +8% (sparse gap 15k cycles), Zen 4 +0% to +3% | running | running | running | `hc/003-sparse-ptr` |
| 004 | 2026-10-09 | wheel | A lone prime (13) skips the fused group loop | +1% to +3% 1T (13 costs ~9k cycles a pass); local Xeon +0.4% to +5.8% | pending | pending | pending | `hc/004-wheel-one-member` |
| 005 | 2026-10-09 | wheel | No masked stores: apply_group unmasked, partial vectors run into padding | +3% to +6% on the AVX2 path (Zen 4 via v5), +1% to +3% with AVX-512; local Xeon +2% to +19% | pending | pending | pending | `hc/005-wheel-unmasked-tails` |
