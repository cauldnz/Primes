# Hill-climbing ledger

| id | date | entry | hypothesis | prediction | Zen 3 1T/16T (median, Δ) | Zen 5 1T/16T (median, Δ) | verdict | commit |
|---|---|---|---|---|---|---|---|---|
| 001 | 2026-10-09 | both | Profile first: where do the cycles go, ours against C5 and Rust? | Base gap sits mostly in the dense phase (local Xeon: dense 128k cycles a pass against Rust's 82k) | Zen 4 (D16as_v5 landed on a 9V74): base dense 114k / sparse 143k / scan 5k cycles a pass, Rust 79k / 135k / 6k | Zen 5: see note | measurement | `3b02d14` (harness) |
| 002 | 2026-10-09 | base | Vector dense resets: one single-bit OR per composite, per SIMD lane, folded by LLVM into constant vector ORs, as the SLP vectoriser does for Rust | +10% to +18% at 1T on Zen, similar at all threads; local Xeon gained 0% to 19% over four rounds | running | running | running | `164f8c1` on `hc/002-vec-dense` |
