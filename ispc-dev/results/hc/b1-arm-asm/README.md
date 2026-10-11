# b1-arm-asm: aarch64 code for the ISPC base vs mike-barber's Rust (bit-extreme-hybrid)

Question: on Cobalt 100 (Neoverse N2) the Rust `--bits-extreme` run beats our base
(`PrimeISPC/solution_2/primes_base.ispc` at hc/champion 1551635) by ~2% at 1 thread.
Static instruction counting only (no llvm-mca, no runs).

## How the asm was made

| Side | Command | Compiler |
|---|---|---|
| ISPC | `ispc -O3 --pic --woff --arch=aarch64 --target=neon-i32x4 --emit-asm primes_base.ispc` (build.sh's aarch64 target) | ispc 1.22.0 / LLVM 17 |
| Rust | `cargo +1.57 rustc --release --target aarch64-unknown-linux-gnu -- --emit asm`, `RUSTFLAGS=-C target-cpu=neoverse-n2` | rustc 1.57 (the Dockerfile's `rust:1.57`), LTO, 1 CGU |

A rustc 1.97 build was also emitted; its sparse loop is worse (8 separate pointers, 35
instr per 8 composites) and its P=3 dense loop uses `st3`. The table uses 1.57, which is what
the Docker image runs. Both sides dispatch on factor < 128 (Rust <= 129) dense, else sparse.

## Sparse loop (p >= 131): one byte RMW per composite, 8 per p-byte chunk

| | ISPC (clear_sparse_e, inlined into clear_factor) | Rust 1.57 (ResetterSparseU8, inlined into run_implementation_st) |
|---|---|---|
| Instr per 8 composites | **29** (3.63/composite) | **28** (3.50/composite) |
| Loads / stores per composite | 1 `ldrb` / 1 `strb` | 1 `ldrb` / 1 `strb` |
| Addressing | `[base, xoff]` reg+reg, offsets in 8 regs | `[base, xoff]` reg+reg, offsets in 8 regs |
| Address calc per chunk | 1 `add` + **2 `mov`** (rotated copies of q / q+p) | 1 `add` |
| Loop control | `add x5,x9,x18; cmp x5,x8; b.le` | `sub x0,x0,x8; cmp x0,x8; b.hs` (remaining-length counter) |
| Unroll | 1 chunk (8 composites) | 1 chunk (8 composites) |
| Bit index | mask is an immediate (`orr w,w,#0x40`); no shift/and | same |

```
ISPC  .LBB107_5:  mov x6,x9 ; mov x9,x5
                  ldrb w5,[x6,x15] ; orr w5,w5,#0x1 ; strb w5,[x6,x15]   (x8)
                  add x5,x9,x18 ; cmp x5,x8 ; b.le .LBB107_5
Rust  .LBB229_27: ldrb w3,[x2,x1] ; sub x0,x0,x8 ; cmp x0,x8 ; orr w3,w3,#0x2 ; strb w3,[x2,x1]
                  ...(x8) ; add x2,x2,x8 ; b.hs .LBB229_27
```

The two `mov`s come from the loop condition `q + p <= end`: LLVM computes `q+p` before the
compare, reuses it as the next `q`, and has to copy registers to rotate it.

## Dense loop (p < 128): one period of P words (P < 16: 4 periods for ISPC)

| P | ISPC instr / words | ISPC per word | Rust instr / words | Rust per word | extra ISPC q-loads (mask reloads) |
|---|---|---|---|---|---|
| 3 | 16 / 12 | 1.33 | 16 / 6 | 2.67 | 0 |
| 5 | 24 / 20 | 1.20 | 11 / 5 | 2.20 | 0 |
| 15 | 64 / 60 | 1.07 | 22 / 15 | 1.47 | 0 |
| 17 | 23 / 17 | 1.35 | 23 / 17 | 1.35 | 0 |
| 31 | 39 / 31 | 1.26 | 38 / 31 | 1.23 | 0 |
| 47 | 55 / 47 | 1.17 | 54 / 47 | 1.15 | 0 |
| 63 | 76 / 63 | 1.21 | 72 / 63 | 1.14 | 7 |
| 97 | 127 / 97 (stores 49 of 97) | 2.6 / composite | 107 / 64 composites | 1.67 / composite | 25 |
| 127 | 169 / 127 (stores 63) | 2.6 / composite | 196 / 64 composites | 3.06 / composite | 39 |

- Both: `ldr q`/`orr v.16b` with a mask register/`str q` per word pair, scalar `ldr x`/`orr x`/`str x`
  for an odd word; constant single-bit masks folded per word, no shift/and anywhere.
  Loop overhead 3-4 instr (`add sub cmp b.hi` vs `sub cmp add b.hi`). Unroll = 1 period.
- P >= 65: Rust's macro emits only the 64 words that hold a composite (scalar where neighbours
  are empty); ISPC does a q-RMW over every word pair that holds one. ISPC also runs out of
  q registers from P ~ 49 and reloads mask vectors from the constant pool each period.

## Per-pass dynamic estimate (instructions, load ops, store ops; thousands)

| Phase | ISPC | Rust 1.57 |
|---|---|---|
| dense p < 64 | 161 / 72 / 69 | 211 / 76 / 76 |
| dense 65..127 | 129 / **75** / 51 | 134 / **46** / 45 |
| sparse | **482** / 133 / 133 | **466** / 133 / 133 |
| total | 773 / 279 / 254 | 811 / 256 / 254 |

(iterations x loop body; prime scan, init and tails excluded.) ISPC executes fewer
instructions overall, but the sparse loop, which is ~60% of the work, has 3.6% more
instructions than Rust's, and the dense 65..127 loops issue ~28k (60%) more loads.

## Most likely cause of the ~2% gap

The sparse loop: same memory ops, but 29 vs 28 instructions per 8 composites, the extra two
being register-rotation `mov`s on the loop-carried pointer path. N2 sustains 8 RMWs per
~5.5-6 cycles here, so one in 29 uops is ~2-3.5% of sparse time, i.e. ~1.5-2% of the pass. The
secondary candidate is the mask-vector reloads in dense 65..127 (+28k loads/pass).

## Next experiment (base rules kept: one OR per composite, no stamping, no segmentation)

In `clear_sparse_e`, compare the chunk pointer against a precomputed last chunk start
instead of computing `q + p` in the condition:

```c
uniform uint8 * uniform last = end - p;          // last whole chunk start
for (; q <= last; q += p) { q[o0] |= m0; ... q[o7] |= m7; }
```

Checked here: aarch64 asm for that loop becomes 28 instructions (`add add cmp b.le`, no `mov`),
equal to Rust's; the x86 build with it passes `PRIMES_TEST=1`. If it holds on Cobalt, the
follow-up is P >= 65 dense: emit scalar RMW for words whose pair-neighbour is empty (as the
Rust macro does) to drop the mask reloads.
