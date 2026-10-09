# Grok47 review: past Rust on Zen 5, and the wheel's two hot loops

Reviewed 2026-10-09 against `ispc-dev` (`140bf30`) and `hc/champion`. Code lines are
`hc/champion`: `PrimeISPC/solution_2/primes_base.ispc` and `PrimeISPC/solution_1/primes.ispc`.
Rivals are mike-barber `PrimeRust/solution_1`, davepl `PrimeCPP/solution_5`, and rogiervandam
`PrimeC/solution_5` only as context. No harness changes and no rule changes are proposed.

## What the measurements actually say

On Zen 5 the base entry and the Rust entry are the same sieve with the same two kernels.
hc-010 (`STATUS.md`, "Where the cycles go") timed both at **38k dense + 61k sparse + 4k scan**
cycles a pass. The morning report then has the uninstrumented base at 123.3k / 987k passes
against Rust at 125.3k / 873k: **−1.6% at 1T, +13.1% at 16T**. The 1T deficit is smaller than
the noise in that same table (Rust's control was 125k in two rounds and 92k–96k in three; the
−1.6% keeps only the full-speed rounds). hc-010 without timers was 123k–125k against 125k.

A pass is about 103k TSC cycles in the three timed phases, plus about 1k of set-up in hc-001.
Two percent, the hill-climb acceptance bar, is about **2k cycles**. Anything under that will
not show up as a Zen 5 1T win. We already win the all-threads comparison, which is the SMT
case: fewer instructions help there, and they have already helped. **1T only moves if a pass
issues fewer store uops.** Both hot loops are at that ceiling:

- Sparse is 133,075 byte ORs (primes 131–997; 8 ORs per chunk of `p` bytes) in 61k cycles,
  **0.46 cycles per store**. Two stores per cycle is a 0.5 floor (Agner, as cited in
  `RESEARCH.md`). Either the loop is already on the floor, or the TSC is slower than the core
  and the true cost is higher. I do not have the 9V45 boost clock from the logs, so I cannot
  tell which. hc-018 (two chunks a trip) was flat, which fits a loop that is already
  store-bound.
- Dense is 63 odd factors below 128, **603 cycles a factor** (38k / 63), a full sweep of the
  7,813-word array. That is about 200 bytes per cycle of read plus write, in line with two
  32-byte stores and four 32-byte loads per cycle. hc-013 added `avx512skx-x8` and gained
  **+1.0%** at 1T. A wider store path is not a free win on this chip, or the dense loop is
  not the code that changed. I am unsure which.

So the 1T gap is not a kernel Rust has and we lack. It is a few thousand cycles, maybe noise,
on top of two loops that already match. The one structural difference left is **how many
factors pay a full-array sweep instead of one store per composite**.

Excluded, so it is not one of the five: cross-factor L1 blocking. The 62.5KB array does not
fit Zen 5's 48KB L1, and applying every factor to a 32KB window before moving on would cut
L2 traffic. That is segmentation. The rules gate in `HILL-CLIMB.md` forbids it ("primes are
not determined by a separate first step"), and so does the brief for this review. Within one
factor, tiling does nothing: each factor already touches each line once.

## 1. Five ideas for the base entry on Zen 5

All five keep a fresh sieve per pass, one bit per odd number, a search over odd numbers from
3, no prime table, and no segmentation. "Base-legal" here means the source still has one
single-bit OR per composite, which is the reading in `RULES-REVIEW.md` and the rules gate.
`CONTRIBUTING.md` (the "clears all non-primes individually" sentence) is looser; davepl's
entry is tagged base and would fail that gate. Do not import his wording.

### 1. Raise `DENSE_LIMIT` from 128 to 192, then 256, with `clear_dense_vec`

- Phase: sparse. Primes 131–251 are 23 of 137 sparse primes and **60,816 of 133,075 stores
  (46%, about 28k of the 61k)**. Primes 131–191 are 12 primes and 37,087 stores (about 17k).
- Cycles: a dense factor now costs 603 cycles and does one vector sweep, not one store per
  composite. 23 × 603 = 14k, against 28k removed from sparse, **net about 8k–14k (8–13% of
  a pass, well past the 1.6%)** if the 603 holds. The old "10k at stake" line in
  `HILL-CLIMB.md` assumed 2.2k against 2.6k–3.3k per factor. That pair is stale; the hc-010
  numbers are the ones to use. Break-even against 0.46 cycles per byte store is around
  p = 400, so 256 is still on the right side of the line and 384 is where I would stop.
- Why it is base-legal: `clear_dense_vec` (`primes_base.ispc:121-138`) already does this for
  every odd factor below 119. Line 132 is one composite:

  `x |= ((t >> 6) == k) ? ((uniform uint64)1) << (t & 63) : 0;`

  The new cases have to be every odd value, not only the primes, same as the switch at
  lines 198–204. LLVM folding those ORs into a constant vector OR is the precedent
  `RULES-REVIEW.md` already accepted for hc-002.
- Unsure: compile time. LEDGER 002 parked this because one target took over 7 minutes past
  factor 128, and `avx2-i32x16` / `avx512skx-x16` failed to fold. `VEC_LIMIT` is 119 for
  that reason (line 58). A rolled outer loop whose body still contains the unrolled
  single-bit ORs, compiled as one translation unit per factor, is the way through the
  compile wall without putting a multi-bit mask in the source. I have not measured a
  factor above 117, so the 603-cycle assumption is the weak point. If a large-P body
  fails to fold and falls back to `vblendv`, it will lose to sparse and should be reverted
  per factor, not kept for the sake of the sweep.

This is the only idea I would bet a Zen 5 1T win on. It is also the idea Rust can copy
with the macro it already has (`extreme_reset` stops at 129). Landing it matters more
than polishing the tied loops.

### 2. Make the sparse byte offsets immediates for factors 131–383

- Phase: sparse, the heavy half. `clear_sparse_e` (`primes_base.ispc:143-169`) computes
  `o0`–`o7` from a runtime `p` (lines 145–148) and walks `q[o0] |= m0` (lines 157–159).
  The masks are already immediates, selected by `p & 15` (lines 174–183). The offsets are
  not: they depend on the whole factor, so the store is `or` with a register offset.
- Cycles: **0–4k at 1T**. At 0.46 cycles per store there is almost no overhead left to
  remove, and hc-018 (two chunks, still register offsets) was flat on both Zen 3 and Zen 5.
  If the TSC under-counts core cycles, a memory-destination `or byte [reg+imm8], imm8` is
  worth more, perhaps half of the gap between 0.46 and a true 0.5–0.7, which I would put
  at 2k–6k and not higher. This is the same change that helps SMT, where we already lead.
- Why it is base-legal: still eight single-bit ORs per chunk, one composite each. A
  `switch` on the factor, covering every odd value in the band (or a generic fallback
  that is the current function), does not assume which of them are prime. It is the same
  shape as the dense switch.
- Unsure: whether LLVM already turns the runtime offsets into immediates when `p` is
  constant after inlining. If the asm of `clear_sparse_e` already shows `imm8` offsets,
  this idea is worth nothing. I have not seen that asm.

### 3. Keep the single-bit ORs, but stop unrolling the block loop

- Phase: dense (38k), and it is what makes idea 1 compilable.
- The blow-up is `#pragma unroll` on both loops in `clear_dense_vec` (lines 124–130):
  the `kb` loop runs `P` vector steps, and each step unrolls
  `64 * programCount / P + 2` ORs. For P = 255 and an 8-wide gang that is a few hundred
  bodies per factor, times every odd factor. Roll the `kb` loop. Leave the inner ORs
  unrolled in an `inline` function of `(P, kb)` so LLVM still folds one vector's ORs into
  one constant, which is the whole of hc-002. The hot loop is then load, OR constant,
  store, for `P / programCount` iterations.
- Cycles: on its own, **2k–5k if** the current fully unrolled bodies miss L1I between
  factors (Zen 5's L1I is 32KB; 63 fat functions do not fit). I have no PMU data. Azure
  could not count instructions (hc-001). The gain I would actually book is "idea 1 becomes
  buildable", not a cycle number.
- Why it is base-legal: line 132 stays in the source. Writing the folded constant into a
  static table by hand would not be. That is davepl's `stepMasks` (see section 5).
- Unsure: ISPC may refuse to fold the inner ORs once `kb` is a real argument rather than
  a fully unrolled constant. The fold has already failed once, for `avx512skx-x16`
  (LEDGER 002). Check the asm for `vblendv` / `vpcmpeq` in `clear_dense_vec` before
  trusting a green self-test. A correct but unfolded kernel is a loss.

### 4. Do not load a word whose old value is known to be zero

- Phase: dense, factor 3 only, plus the initial zero.
- `sieve_create` zeros every word (`primes_base.ispc:77`), then `clear_dense_vec` loads
  it back (`line 127`: `uint64 x = w[c + k]`). Factor 3 hits every word (step 3 is less
  than 64). A pure store of the register built by the same single-bit ORs replaces the
  zeroing write and the factor-3 load. davepl does the store-instead-of-OR half of this
  as `mark_multiples_empty` for the first factor only (`PrimeCPP_array.cpp:700-703`).
  His version stores a multi-bit mask. Ours must still build that register with line 132.
- Cycles: hc-001 put set-up at about 1k. Dropping the extra write of 62.5KB is at most
  another 1k–2k if those stores are not hidden behind factor 3's own stores. **I do not
  expect this to clear 2% by itself.** Load ports are slack next to two store ports, so
  the load at line 127 is probably free at 1T.
- Why it is base-legal: the operation that clears a composite is still the single-bit OR.
  The load is not part of the algorithm. It applies only while the buffer is still the
  zeros we just wrote. Extending it to later factors ("this word has not been touched
  yet") is segmentation, and I would not do it.
- Unsure: ISPC's `foreach` zero may already be a 64-byte store stream that the factor-3
  sweep overlaps in the store buffer. If it does, the measured gain is ~0.

### 5. Count the sparse chunks instead of comparing pointers

- Phase: sparse.
- The hot loop (`primes_base.ispc:157-160`) is `for (; q + p <= end; q += p)` and then
  eight ORs. A trip count (`nchunks`, one decrement and branch) is one fewer uop per
  chunk. There are 133,075 / 8 ≈ 16,600 chunks. One uop saved, at about 6 uops per cycle,
  is about **3k cycles** if that uop is not already hidden, and about 0 if the loop is
  in the loop buffer and store-bound. hc-018 is evidence for 0.
- Why it is base-legal: the eight ORs and the set of composites do not change. The tail
  (lines 161–168) stays.
- Unsure: this is the weakest of the five. I include it because it is the only sparse
  change left that is not a replay of hc-003 (pointer walk, already merged) or hc-018
  (two chunks, reverted), and because the 16T win shows the core still has front-end
  slack when a sibling is running. At 1T I would not be surprised by a flat result.

What I would not spend a run on: another AVX-512 width (hc-013 was +1.0%, and
`avx512skx-x16` does not narrow the store; an 8-lane zmm and a 16-lane zmm are both
64 bytes), a count-trailing-zeros scan (hc-009, −1.4% on Zen 5; the scan is 4k in both
entries), or a dense limit above ~320 without a new kernel. Moving primes from sparse
into dense is a win only while one vector sweep is cheaper than one store per composite.
Past that point the sweep is the more expensive of the two, which is why 128 was right
when dense was scalar and is too low now that dense is a vector sweep.

## 2. Three ideas for the wheel

hc-010 on Zen 5: **sparse loop 52% of samples, fused groups 35%, tile plus 13 the rest.**
The champion is past the research prototype: lone-prime 13 (hc-004), no lead-ins (hc-016),
64-bit indices without the spill (hc-015), G = 6 on AVX-512 and unmasked tails on AVX2
(hc-021). The three ideas below are what that profile still points at. A pass at the
morning-report 179.6k is 27.8 µs. I do not know the 9V45's boost, so the cycle numbers
assume 3.5 GHz (about 97k core cycles a pass). If the chip is closer to 2.6 GHz the
savings shrink by the same ratio. Treat the percentages as firmer than the cycle counts.

Sparse work is concrete: primes 257–997, 114 primes, about **56,700 single-bit marks**
(8 planes, ~33,334 bits each, stride `p`). At 52% that is about 0.9 core cycles per mark
under the 3.5 GHz assumption, against a 0.5 floor. Groups are 8 planes × 521 words,
G pattern loads plus one sieve load per word. With G = 6 that is about 29k loads, 7k
cycles at four loads per cycle, against ~35% of the pass (about 34k cycles). Groups are
several times their load floor. Both estimates are soft.

### 1. Sparse: a byte kernel, retested on Zen 5, not the old Xeon result

- Phase: `sparse_prime` (`primes.ispc:239-262`), 52%.
- The hot statement is line 254:

  `base[i[pl] >> 6] |= ((uniform uint64)1) << (i[pl] & 63);`

  That is a 64-bit load, a variable shift, an OR and a 64-bit store, per mark. Eight
  marks of one plane span exactly `p` bytes, with masks fixed by the start bit and
  `p mod 8`. That is the base entry's `clear_sparse_e`, one plane at a time, eight
  planes in the loop. A byte OR with an immediate mask is one memory-destination uop,
  not a shift.
- Cycles: if the loop is really at ~0.9 cycles per mark and a byte OR reaches 0.5,
  the spare is about **25k cycles, a quarter of the pass**. I do not believe the full
  amount. `wheel_byte_sparse.ispc` was **9% slower** on the Xeon sandbox (`RESEARCH.md`,
  tested and rejected), where one store per cycle makes a byte OR and a word OR the
  same store. Zen 5 has two store ports and a more expensive variable shift, so the
  sign can flip. I would book **0 to +12% of the pass** and keep the word form if the
  first Zen 5 A/B is negative. Do not tune this on the sandbox; LEDGER 003 already
  showed the sandbox ranking the sparse loop differently from Zen 5.
- Legal for a wheel entry. It does not change storage, the mod-30 planes, or the
  one-bit-per-mark shape. No rule issue.

### 2. Sparse: eight real pointers, and a rotate instead of a variable shift

- Phase: the same loop, if idea 1 loses.
- `i[pl]` is a 64-bit bit index. Every mark recomputes the word and the bit. Split it
  once, at the start of `sparse_prime`: a `uint64 *` per plane and a mask. The step in
  words is `p >> 6`, plus one when the bit wraps. The mask update is a rotate by
  `p & 63`. Specialise that rotate on `p & 63` (32 classes, not 114 primes) so the
  rotate is an immediate. The inner loop is then eight independent `*wp |= mask; wp +=
  step`.
- Cycles: this is the same 0.9-versus-0.5 gap, reached by deleting the shift rather
  than by changing the store width. **5–15% of the pass** if the shift and the
  `>> 6` are why the loop misses the floor; **~0** if the samples are L1 misses from
  the stride (p = 257 steps about 32 bytes, so almost every mark is a new line, and
  the 33KB of planes do fit in a 48KB L1, so I think the lines hit). The stride-miss
  story is the part I am unsure of.
- The inner `for (pl)` at lines 253–256 has to unroll. ISPC should unroll a `uniform`
  loop of 8. If the asm still has that loop, unrolling it by hand is the whole idea.
  Adding a second prime in the same loop (16 streams) is the HILL-CLIMB wheel item 7.
  I would not do it until one prime fills the two store ports; extra streams do not
  help a store-bound loop, and hc-012's 16T loss was exactly extra reloads on shared
  load ports.

### 3. Fused groups: shrink `Group`, then replace two pattern loads with arithmetic

- Phase: `apply_group` (`primes.ispc:176-213`), 35%. The OR is line 199:

  `v |= g->pp[j][r[j] + programIndex];`

- `Group` holds `buf[G][MAXPAT + 64]` with `MAXPAT` 1024 (lines 53 and 83). At G = 8
  that is about 70KB. `dense_max` is 256 (`main`, line 421). The patterns actually
  used are 256 words plus a gang, about 15KB at G = 6 and 20KB at G = 8. Planes are
  33KB. **70KB of scratch plus 33KB of planes cannot share a 48KB L1; 15KB plus 33KB
  can.** HILL-CLIMB already has this as wheel item 5. It was never run. I would expect
  **3–8% of the pass** on Zen 5 if group time is L1 misses on the pattern table, and
  less on Zen 3, whose L1 is 32KB and will still spill. Unsure, because a 16-wide gang
  has enough loads in flight to hide L2 hits. The change is a bound, not an algorithm
  change. No rule risk.
- After that, arithmetic masks for two of the G members (RESEARCH idea 7). For a prime
  above 64 a word holds at most one bit of that prime, so the lane mask is a shift of
  a running position, not a load. Groups are load-heavy (G + 1 loads per store) and
  Zen 5 has four load ports and a lot of ALU. Moving two members off the load ports
  balances the iteration. **0–8% of group time, so 0–3% of the pass.** The research
  note was right to call this uncertain. I would not try it before the scratch shrink,
  and I would not move more than two members: the shift then becomes the bottleneck
  the load used to be.
- Not worth another run: G itself (G = 6 is already the AVX-512 champion), the 7·11
  tile copy (hc-008, flat; it is 2–3% of a pass in the old profile and less now), and
  a mod-210 wheel (RESEARCH section 5.9: planes of ~74 words make the fixed cost worse).

## 3. Making mike-barber's Rust faster, same algorithm

Same hybrid: dense extreme-reset for every odd skip ≤ 129, sparse byte reset above that.
"Same algorithm" means those two kernels and the outer search stay. A higher dense cutoff
is a parameter, not a new algorithm. Nothing here should be submitted without asking him;
`CONTRIBUTING.md` requires that, and `HILL-CLIMB.md` already says so.

1. **Raise the dense cutoff past 129.** `unrolled_extreme.rs:36` sends `skip > 129` to
   `ResetterSparseU8`. The macro in `helper-macros/src/lib.rs:274` stops at 129. The same
   arithmetic as idea 1 applies: primes 131–251 are ~28k of our shared 61k sparse cycles,
   and a vector sweep at ~600 cycles a factor is cheaper up to about p = 400. Rust will
   compile this. ISPC may not. If this lands in Rust and not in ISPC, the Zen 5 1T gap
   opens again, by roughly the 8–13% above. This is the change that matters.

2. **Stop disabling AVX-512.** `.cargo/config:3-10` sets `target-feature=-avx512f` on both
   x86 targets, for a Skylake Xeon problem. Zen 5 is not that Xeon. hc-013 was only +1.0%
   for our dense loop, so I would expect **0–3%**, not a repeat of hc-002. The SLP
   vectoriser is why Rust's dense is fast (`extreme_reset_word`, `lib.rs:243-251`, one
   load, N single-bit ORs, one store, every word, including words with no masks). The
   empty-word store is what gives LLVM a straight scan to vectorise. Do not "fix" the
   dead `TokenStream::default()` at lines 239–241. RESEARCH.md is right that the bug is
   the vectoriser's input.

3. **Pointer-walk the sparse loop.** `ResetterSparseU8::reset_sparse`
   (`unrolled.rs:247-278`) is `chunks_exact_mut` plus a runtime `relative_indices` array.
   Our hc-003 pointer walk was +12.3% at 1T on Zen 5 when our sparse loop was
   instruction-bound, and then the two entries tied at 61k. So LLVM may already be
   emitting our loop. An A/B is cheap. I would expect **0–3% of sparse (0–2k cycles)**
   and would revert if the iterator form is what SLP or the loop unroller prefers.
   Eight immediate masks are already there (`SINGLE_BIT_MASK_SET`). The indexes are the
   part that still moves.

4. **Do not merge the two kernels.** A word mask that sets every hit in the word in one
   OR, which is davepl's `stepMasks`, would be faster and would be a different algorithm
   under the rules this tree uses. It is also unnecessary: the proc-macro form already
   matches our best dense kernel.

## 4. Rule risk in the current code

I do not see a base-algorithm break in `primes_base.ispc`. The line that keeps it legal
is the one to avoid "cleaning up":

```
primes_base.ispc:132
x |= ((t >> 6) == k) ? ((uniform uint64)1) << (t & 63) : 0;   // one composite
```

The sparse loop is the same promise, eight times (`primes_base.ispc:158-159`). The switch
lists every odd factor, composites included (lines 198–204). That is what "no prime
knowledge beyond 2" requires. The chunk start is before `p²`:

```
primes_base.ispc:122
uniform int c = ((P * P / 2) / 64 / P) * P;
```

`RULES-REVIEW.md` already accepted this. Clearing starts at the chunk that holds `p²`,
re-marks composites below `p²`, and restores `p` (`clear_dense_from`, lines 107–108,
reached from the vector path at line 137). I would leave it. A reviewer who wants the
clear to start at `p²` exactly can still object. I think that objection loses, because
the original C++ started at `3p`, and `CONTRIBUTING.md` allows `p²`.

The wheel risk is the retag, not faithfulness. `RULES-REVIEW.md` already says a reviewer
can call the pattern streaming "other". The line they would quote is the copy of the
7·11 tile, which writes a multi-bit pattern in one store per word:

```
primes.ispc:286-288
for (uniform int base = t; base < nw; base += t) {
    uniform int n = min(t, nw - base);
    foreach (k = 0 ... n) w[base + k] = w[k];
}
```

and the fused OR, which sets every bit in a pattern word in one operation:

```
primes.ispc:199
v |= g->pp[j][r[j] + programIndex];
```

Both are legal for a wheel entry. Spångberg's wheels are the precedent named in the
rules review. I would not retag pre-emptively. I would also not add a second pattern
stage (13 into the tile, or a 13·17 tile) without expecting the question again.

Two accuracy problems, not algorithm breaks. They matter because `CONTRIBUTING.md` treats
a wrong label as grounds for rejection, and a wrong README is how a reviewer gets there.

- `PrimeISPC/solution_2/README.md:14` says "the build leaves AVX-512 out" and that Rust
  "ran 15% faster on Zen 3 and 31% faster on Zen 5". Neither is true of `hc/champion`.
  `build.sh:10` is `sse4-i32x4,avx2-i32x8,avx512skx-x8`. The morning report has the base
  entry ahead on Zen 3 and Zen 4 and level on Zen 5 at 1T. The badges on lines 3–6 are
  still the right ones.
- `solution_2/build.sh:10` compiles arm64 as `neon-i32x4`. The wheel default was moved
  to `neon-i32x8`. The base NEON path is the scalar dense routine (`primes_base.ispc:188-189`),
  so the gang width may not matter. I have not checked. hc-020 is why that scalar path
  must stay: the vector dense code is per-lane loads on NEON and was 39% slower on
  Cobalt 100.

No faithfulness break stood out. `struct Sieve` holds the bits, and on the wheel the
pattern scratch too (`primes.ispc:86-94`). Both are allocated in `sieve_create` and freed
in `sieve_destroy`, once per pass. The residue and inverse tables are `static const`.
That is the reading `RULES-REVIEW.md` already signed off.

## 5. What davepl's `mark_multiples` does, and what carries over

`PrimeCPP/solution_5/PrimeCPP_array.cpp`, `mark_multiples_impl` at line 254. The outer
loop (`runSieve`, lines 679–711) is still the base search: next zero bit, then clear from
`factor²`. `find_next_prime_bit` (lines 203–217) is a word scan with `__builtin_ctzll`.
We tried that as hc-009 and lost 1.4% on Zen 5. It does not carry over as a win. The
scan is 4k cycles in both of our timed entries.

The clear has two kernels, split at line 263:

- **Large step** (`bitStep >= 64`, or `>= BITSTEP_WORDWISE_THRESHOLD` when not
  overwriting). Eight byte marks, pointer walks by `bitStep` bytes (lines 284–294).
  Masks and offsets are computed from the true start bit (lines 271–276), so the clear
  starts at `p²` exactly and does not restore `p`. That is the same kernel as
  `clear_sparse_e`, with a tighter start. Starting at `p²` instead of the chunk boundary
  saves a handful of ORs per prime, not a measurable number at 61k. The shape carries
  over; we already have it. His loop is counted (`groupsLeft`), which is idea 5 above.
- **Small step.** `stepMasks[64]` (lines 328–348) builds, for each residue, **one 64-bit
  mask with every hit bit in the word set**. The hot path ORs that mask once per word,
  in a repeating block, with AVX-512 / AVX2 / SSE / NEON loads of 8 / 4 / 2 masks
  (lines 398–422 for the AVX-512 case). One instruction clears several composites.
  That is the operation `RULES-REVIEW.md` says was refused as base. It does not carry
  over into `solution_2`. It would also throw away hc-002: the accepted form is the
  single-bit OR in the source, merged by the compiler, not a mask written with several
  bits set.

The first factor takes `mark_multiples_empty` (lines 700–703), which stores the mask
instead of OR-ing it, because the buffer is zero. The idea carries over, as idea 4,
only if the stored register is still built with one OR per composite. Copying
`apply_word<true>` with `stepMasks` does not.

`BITSTEP_WORDWISE_THRESHOLD` is 64, tuned on an M2 Mac (lines 48–52). On Zen 5 our
vector sweep is cheaper than a byte loop up to about p = 400, so his threshold is the
wrong way up for this machine. I would not import the constant.

His entry is badged `algorithm=base`. Under this tree's rules gate it is not a base
entry, because of `stepMasks`. That is his submission, not ours. The part worth copying
is the exact `p²` start and the first-factor store, and neither is where the Zen 5
cycles are.

## Order of work

1. Idea 1, at 192 first, with idea 3's rolled block loop so it compiles. One factor
   band, Zen 5 and Zen 3, arm64 gate because `clear_dense_vec` is shared. Predict
   +5% at 192 and +8–13% at 256 on Zen 5 1T, if the asm still shows constant vector
   ORs. If the fold fails, stop. Do not raise Rust's cutoff in the same week unless
   the goal is to make Rust faster rather than to beat it.
2. Wheel idea 3, the scratch shrink. Small, no rule risk, and it is the 35% phase.
3. Wheel idea 1 on Zen 5 only, one A/B against `sparse_prime`. Revert if it is not
   at least +2%. The Xeon result is not evidence either way.
4. Base ideas 2, 4 and 5 only after idea 1, and only if a same-node five-round median
   still trails Rust. I am not convinced that median exists.

## Claims I am unsure of

- The 603 cycles per dense factor holding for P > 117. Everything in section 1 rests
  on it, and the only evidence is the average over factors below 128.
- The 0.46 cycles per sparse store being a core-cycle number rather than a TSC number.
  If the core runs well above the TSC, both "already on the floor" conclusions are
  wrong, and ideas 2 and 5 get bigger.
- The wheel's 0.9 cycles per mark. It assumes 3.5 GHz. The 52% sample share does not.
- Whether `clear_sparse_e` already has immediate offsets in the asm.
- Whether shrinking `Group` moves the 35%. A 16-wide gang may already hide the L2 hits.
- hc-013's +1.0% meaning "512-bit stores are not faster here". It may only mean the
  dispatcher did not land in the new target for the dense loop. I did not diff the asm.
