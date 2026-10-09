# Research notes: what the leaders do, and what to try next

Written 2026-10-09 by a research agent for the hill-climbing session. It covers the leaders'
source, the sieve literature, ISPC-specific tricks, a ranked list of new ideas, a view on a third
entry in the "other" lane, and proposed additions to the `HILL-CLIMB.md` backlog.

All new timings here come from the shared 4-vCPU Intel Xeon sandbox (2.1GHz TSC, AVX-512
capable, pinned to one core with `taskset`). Pass counts on that box swing by 10% between runs
of the same binary, so the TSC phase counters are the firmer evidence. Nothing here has run on
Zen yet. Prototypes are in `ispc-dev/prototypes/research/`; each one exits after the
single-threaded run.

## 1. Where the cycles go

### Base entry (main session's profile, per pass)

| Phase | ours | mike-barber Rust |
|---|---|---|
| dense, factors below 128 | ~128k | ~82k |
| sparse | ~65k | ~60k |
| next-prime scan | ~7k | ~7k |

The dense phase holds two thirds of the gap.

### Wheel entry (new, `wheel_phase_prof.ispc`, avx2-i32x16, three runs)

| Phase | cycles per pass | share |
|---|---|---|
| 7·11 tile and copy | 3.6k–4.4k | 2–3% |
| 13 on its own | 8.7k–10.4k | 6% |
| dense groups (6 groups of 8 primes, 17–251) | 68k–81k | 45% |
| sparse (114 primes, 257–997) | 66k–78k | 43% |
| total | 154k–180k | |

Three things stand out:

- The prime 13 alone costs 70% of a full group of eight. `apply_group` always streams G
  patterns, so a one-member group loads seven zero patterns for nothing.
- A dense group costs about 12k cycles for 4,168 words, or 2.9 cycles per word. The loads it
  issues (nine 8-byte streams per word) would take about 1.1 cycles per word at two loads per
  cycle. The rest goes on the scalar phase updates, cache-line splits on unaligned pattern loads,
  and 64 lead-in calls per group (8 members × 8 planes).
- The sparse phase sets about 58,000 bits per pass (the sum of 8 × 33,334/p over primes 257 to
  997). That is about 1.2 cycles per bit, close to the one-store-per-cycle limit of this Intel
  core. Zen 3 and later can retire two stores per cycle, so the floor there is lower.

## 2. What the leaders do

### rogiervandam, `PrimeC/solution_5` (other; leads "other", second faithful 1-bit overall)

- Extend algorithm. It sieves the odds-only array by 3, copies the 3-period pattern, adds 5,
  copies the 15-period pattern, and so on. Each new prime extends the pattern by its own factor
  until the product passes the sieve size. Pattern copies use 32-bit words with funnel shifts
  (`continuePattern_shiftleft/shiftright`), so the copy works at any bit offset.
- Stripe kernels chosen by step size: register-rotated vector masks for steps below 64 bits
  (`smallstep_rotate_pair`: the next mask is `(m << s) | (m >> (step − s))` per lane, applied in
  pairs); precomputed vector masks for steps below 128–512 bits; byte-level unrolled loops with
  eight constant masks above that.
- Block-by-block striping for larger primes, with the block size and thresholds picked by a short
  benchmark at start-up (`sieve_tune.h`: algorithm 1 or 2, vector width 128/256/512, stripe and
  large-step cut-offs, block size). Tuning runs before the timed loop.
- One `malloc` for struct and bits, aligned to 256 bytes; mimalloc via `LD_PRELOAD` in the
  Alpine image; OpenMP threads; 32-bit counters. The README reports that 8-bit storage access
  beat 64-bit on modern cores.

### mike-barber, `PrimeRust/solution_1` extreme-hybrid (base)

- Dense factors up to 129 (all odd values, prime or not): a procedural macro writes one function
  per factor. For each word of a P-word chunk it emits load, one `|=` per composite with an
  immediate mask, store.
- A quirk matters. `extreme_reset_word` builds `TokenStream::default()` for words with no
  composites but never returns it, so every word of every chunk gets a load and a store. For
  P above 64 that touches words that need nothing, but it gives LLVM a fully contiguous
  load-OR-store sequence, and the SLP vectoriser turns it into 256-bit ORs with constant
  vectors. That explains the flat ~2,700 cycles per factor the main session measured.
- Sparse: bytes, eight constant masks chosen by `pattern_equivalent_skip` (p mod 16), same as
  ours.
- `target-cpu=native` with `-avx512f`; Debian, not Alpine, because Alpine's malloc was slow.

### GordonBGood, Chapel `solution_1`, Nim `solution_3`, Haskell `solution_2` (base)

- Same hybrid: dense below 129 (Chapel `HYBRID_THRESHOLD = 63` as an index, so factor 129),
  sparse "extreme" byte loops above.
- Chapel's dense kernel is scalar: `v = rp(i1); v |= m1; rp(i1) = v; v = rp(i2); …` with the
  64 masks as `param` constants and a computed-goto table. Scalar code at one word per store
  still reaches 117.9k on the Threadripper, ahead of everyone at 1T.
- The sparse kernel indexes a 64-entry table of classes by (p mod 8, start mod 8); only four
  entries are used because every start is p².
- Chapel reports only a 4-thread multi-threaded result, on principle.

### danielspaangberg, `PrimeC/solution_2` (wheel)

- Wheels from 8of30 to 5760of30030, stored as odd bits. The "owrb" variants only write bits the
  outer loop will read. Simple scalar loops; 60.9k on the Threadripper. Our wheel already runs
  at about twice that.

### Other faithful 1-bit entries

fvbakel `PrimeC/solution_3` (other, word-level segmented) and serg-gini `PrimeD/solution_3`
(base, bit-unrolled hybrid) sit at 30k–70k on the Threadripper. Neither has a technique the
leaders above lack.

## 3. Literature

- primesieve (Kim Walisch). Segments sized to L1 or L2, a mod-30 byte wheel with eight flags per
  byte, and an `EratSmall` loop that crosses off eight multiples in 11 x86-64 instructions (1.375
  per multiple). Pre-sieving of primes up to 163 uses 16 tables of two or three primes each
  ({7, 23, 37}, {11, 19, 31}, {13, 17, 29}, {41, 163} …), combined four at a time by AND, with
  AVX-512 and SVE paths. The tables are static, so a faithful entry can't copy that part, and
  at 10^6 a two-prime table of period p1·p2 words is longer than our 521-word plane for most
  pairs (see idea 9).
  [ALGORITHMS.md](https://github.com/kimwalisch/primesieve/blob/master/doc/ALGORITHMS.md),
  [PreSieve.cpp](https://github.com/kimwalisch/primesieve/blob/master/src/PreSieve.cpp)
- Tomás Oliveira e Silva's bucket sieve: each segment holds a list of only those large primes
  that hit it. It pays when primes are much larger than the segment. Our largest prime is 997
  and the whole sieve fits L1/L2, so it doesn't apply at 10^6.
- Wheel factorisation (Pritchard, "A sublinear additive sieve", CACM 1981; Sorenson's compact
  sieves). These support a mod-210 wheel (48 planes) in principle. At 10^6 the planes shrink to
  about 74 words, shorter than the 16-word gang times the lead-in cost, so the fixed costs we
  measured above would grow.
- Instruction costs from [uops.info](https://uops.info/html-instr/VMASKMOVPD_M256_YMM_YMM.html):
  a 256-bit `vmaskmovpd` store is 18 uops at one per 6 cycles on Zen+, Zen 2, Zen 3 and Zen 4,
  against 3 uops at one per cycle on Skylake, Ice Lake and Alder Lake-P. AVX-512 masked stores
  (k-register) don't have this problem. Agner Fog's microarchitecture guide gives Zen 3 to Zen 5
  two stores per cycle, against one on Skylake.
- AVX-512 `vpternlogq` merges three pattern streams in one instruction. It helps only if the
  ORs are the bottleneck. Our phase profile says the loads and scalar bookkeeping are, so it
  ranks low.

## 4. ISPC techniques that matter here

From the [ISPC performance guide](https://ispc.github.io/perfguide.html), the
[user guide](https://ispc.github.io/ispc.html) and today's experiments:

- `uniform` everything that is the same across lanes; it keeps loop counters scalar and
  unrollable.
- `unmasked { }` in any non-inlined static function that runs with all lanes on. Without it the
  base dense prototype compiled every load and store to `vmaskmovpd` (2,304 of them), because
  ISPC can't prove the caller's mask is all-on.
- Lane-constant folding. `programIndex` is a constant vector, so a condition such as
  `(t >> 6) == w0 + programIndex` with compile-time `t` and `w0` folds to a constant mask, and a
  chain of `v |= cond ? bit : 0` folds to one vector OR with a constant. This is the ISPC route
  to what Rust gets from the SLP vectoriser. It is fragile: with avx2-i32x16 and long unrolls
  the folding failed and ISPC emitted run-time `vpcmpeqd`/`vblendvpd` (passes fell to 3.6k).
  Check the asm after every change.
- Targets: `avx2-i64x4` gives exactly one 64-bit word per lane in one ymm, the natural shape for
  64-bit sieve words. `avx2-i32x16` and `avx512skx-x16` double-pump and won for the wheel.
- Short vector types (`uniform uint64<4>`) and `streaming_store`, `prefetch_l1`/`prefetchw_l1`
  exist. Streaming stores bypass the cache, which is wrong for a sieve that lives in L1. Prefetch
  has nothing to fetch when the working set is already in L1.
- Hidden divides: still worth grepping. The base build has 16 `div` instructions and the wheel
  two, all in set-up code (start bits, `% 30`), not in the hot loops.

## 5. Ranked ideas

Gains are per pass at one thread unless stated. "Rules risk" is the chance a reviewer objects.

### 1. Base: vector dense kernel through lane-constant ORs

- Phase: dense (128k cycles, 64% of the pass).
- Change: write each superchunk of K·P words as gang-wide loads; for each composite, OR its
  single bit into the lane that holds its word (`v |= ((t >> 6) == w0 + programIndex) ? bit : 0`);
  words past the last full vector get scalar ORs. Superchunks avoid the store-forwarding stall
  that a vector overlapping the next chunk causes (the first attempt, which did overlap, ran 25%
  slower).
- Evidence: `base_lane_dense.ispc`, self-test passes, three interleaved rounds:

  | build | passes (3 rounds) |
  |---|---|
  | current, avx2-i32x8 | 34.9k, 36.1k, 35.1k |
  | lane, K=1, avx2-i32x8 | 38.5k, 39.5k, 39.6k |
  | lane, K=2, avx2-i32x8 | 41.2k, 35.9k, 39.3k |
  | lane, K=1, avx2-i64x4 | 37.7k, 39.2k, 35.6k |
  | lane, K=2, avx2-i32x16 | 3.6k (folding failed) |

  K=1 at i32x8 gains about 12%.
- Expected gain: 10–20%. If dense falls to Rust's ~82k, the pass drops from 200k to 154k
  cycles, which would be 30% more passes; the sandbox shows 12%, so the kernel isn't there yet.
- Effort: half a day to land; a day with a sweep of K and targets on Zen.
- Rules risk: low to medium. The source still has one single-bit OR per composite; the compiler
  merges them, which is the accepted Rust and Chapel precedent. Explain it in the README.
- Sources: Rust macro quirk above; ISPC lane folding observed here.

### 2. Wheel: no masked tails on AVX2

- Phase: dense lead-ins and tails, tile, 13.
- Change: the fused loops are unmasked already, but each `apply_range` lead-in and each plane tail
  ends in `vmaskmovpd` loads and stores: 148 of them in `apply_group` alone. My estimate is
  about 2,000 masked stores per pass: four per tail, nine tails per plane (eight lead-ins and the
  plane end), eight planes, six groups, plus the tile and 13. Pad planes to a multiple of the gang (`pw` to 16 words, not
  8) and let the last vector run past the end unmasked. Overrunning is safe because ORing a
  prime's own pattern is idempotent: words past `start` get those bits again in the fused loop,
  and words past `nw` are padding that `count_primes` ignores.
- Expected gain: 3–6% on Zen 3 with `avx2-i32x16`, the path runner 74 uses. 2,000 masked
  stores at one per 6 cycles is at least 12k cycles, against about 215k per pass on Zen 3. Near
  zero on Intel and on the AVX-512 path, so the sandbox can't measure it.
- Effort: two to four hours.
- Rules risk: none.

### 3. Wheel: one-member groups skip the fused loop

- Phase: 13 on its own.
- Change: when a group has one member, call `apply_range` per plane directly
  (`wheel_one_member.ispc`, five lines).
- Evidence: 13 fell from 8.8k–10.4k to 2.1k–2.3k cycles per pass in three paired runs. Pass
  counts in five interleaved rounds: median 74.2k against 73.4k, inside noise.
- Expected gain: 3–4%.
- Effort: an hour.
- Rules risk: none.

### 4. Base: raise the dense limit once dense is vectorised

- Phase: dense and sparse.
- Reasoning: a vector dense factor costs about the same whatever P is (~2.7k cycles in Rust); a
  sparse factor at P = 131 sets about 3,800 bits at roughly one cycle each. Dense should win up to
  roughly P = 180–250. Sweep 128, 192, 256 after idea 1 lands.
- Expected gain: 2–4%. Compile time and code size grow; watch i-cache.
- Effort: an hour plus Azure time.
- Rules risk: low; dense must still cover every odd value, prime or not.

### 5. Both: start-up autotune of thresholds and gang

- Phase: all.
- Change: before the timed loop, time a few hundred passes for each of 2–4 settings (dense
  limit; wheel G; gang width via separately compiled functions) and keep the fastest, as C5 does
  (`sieve_tune.h`).
- Expected gain: 0–5%, mostly as insurance for runners we can't test, such as runner 74's
  unknown EPYC host behind a generic CPU model.
- Effort: a day.
- Rules risk: low; C5 does it and nothing persists into the timed passes. State it in the README.

### 6. Wheel: cut lead-in overhead

- Phase: dense groups.
- Reasoning: each group makes 64 `apply_range` calls (8 members × 8 planes), each with a scalar
  first word, a vector loop and a tail. With idea 2 done, measure what remains with the phase
  counters. If it is still above 1k cycles per group, start every member at the earliest
  member's start word, so no member needs a lead-in. Later members then mark multiples below
  their own p², which are composite anyway, and also mark p itself, so clear each member's own
  bit afterwards, as the base entry already does. The read-ahead rule still holds, because
  candidates are only read below g0² and no prime other than the members gets marked.
- Expected gain: 2–5%, unmeasured.
- Effort: half a day.
- Rules risk: none.

### 7. Wheel: mix arithmetic masks with pattern loads

- Phase: dense groups.
- Reasoning: the HANDOFF idea. For primes above 64 each word holds at most one bit, so a lane's
  mask is `(pos < 64) ? 1 << pos : 0` with `pos` stepping down by 64·gang mod p. That costs ALU
  ops instead of a load and a possible line split. Moving two of eight members to arithmetic
  could balance load and ALU ports.
- Expected gain: 0–8%, uncertain.
- Effort: a day.
- Rules risk: none.

### 8. Base: next-prime scan by word

Already backlog item 2. The scan costs ~7k cycles, so `count trailing zeros` on the inverted word
saves at most 3%. Low effort, low risk.

### Tested and rejected today

- Wheel, byte-level sparse with 32 constant-mask variants (`wheel_byte_sparse.ispc`): 9% slower
  over five rounds. The present eight-plane interleaved loop stays.
- Wheel, folding 13 into the first group: the group then flushes early at 169 and makes seven
  groups; net gain 1–2% in cycles. Idea 3 does better.
- Wheel, G = 12 and G = 16 (with `MAXPAT` 320): slower than G = 8 in four rounds, probably
  register spills (16 phase indices and 16 pointers exceed the 16 general registers). G = 8 with
  `MAXPAT` 320 showed no gain. Backlog item 3 can drop 12 and 16 from its sweep.

### 9. Considered and set aside

- primesieve-style two-prime pattern tables. A pair table is shareable across the eight planes
  (64 is invertible mod p1·p2, so by the Chinese remainder theorem one word rotation reaches any
  pair of offsets), but building one costs about p1·p2 word writes plus 64·(p1 + p2) bit sets,
  2k–3k cycles, while it saves one load per four words, about 500 cycles across eight planes.
- `vpternlogq` merging: ORs aren't the bottleneck.
- Mod-210 wheel: planes of about 74 words make the per-plane fixed costs above worse.
- Bucket sieve, streaming stores, software prefetch: the sieve fits L1/L2 at 10^6.
- Precomputed pre-sieve tables in the binary: not faithful.

## 6. A third entry in the "other" lane?

### What "other" permits

`CONTRIBUTING.md` defines "other" as anything that is neither base nor wheel. Faithfulness
applies the same way: a class-equivalent holding all state, a fresh instance each pass, a
run-time buffer sized to the sieve, and no external sieving code. "Other" unlocks no technique
the wheel entry can't already use. The wheel tag only asks that wheel factorisation be the main
characteristic.

### What rogiervandam does that we don't

- Pattern extension through 3, 5, 7, 11, 13 and 17 on the odds-only array. Our wheel covers 2,
  3 and 5 by storage and 7 and 11 by a copied tile.
- Block-by-block striping of a 62.5KB array. Our 33KB wheel planes fit L1 already.
- Register-rotated masks for steps below 64 bits.
- Start-up tuning, mimalloc, OpenMP. Tuning is idea 5; mimalloc can't be used without a
  non-libc dependency, and the allocator is outside the sieve, so it is a Dockerfile question.

### Numbers already in hand

On the sandbox, one thread, three interleaved rounds: the odds-only `sieve2.ispc` prototype
~47k, C5 ~56k, our wheel ~62k. On Azure (STATUS.md) the wheel with `avx2-i32x16` beats C5 at
one thread by 25% on Zen 3, 0.4% on Zen 4 and 5% on Zen 5, and trails it by 2% at 16 threads on
Zen 5.

### What winning "other" would take

An ISPC odds-only entry would need about 19% more than `sieve2` on the sandbox just to tie C5,
and more on Zen 5, where C5 is strongest. The path would be C5's extension through 17 (a
255,255-bit pattern, 3,988 words, inside the 7,812-word array), vector fused groups for 19–255,
and 16KB blocking for the sparse primes. Estimate: three to five days of work plus about NZ$20
of Azure time. I'd put the chance of beating C5 on Zen 5 at about one in three.

### Recommendation

Don't build solution_3 now.

- The leaderboard's faithful 1-bit view ranks all algorithms together. Our wheel already beats C5
  at one thread there, so an "other" entry would rank below our own wheel. It would only win
  the "other" filter.
- If a reviewer retags the wheel as "other" (RULES-REVIEW.md flags the risk), the wheel becomes
  our "other" entry and already beats C5.
- A third entry from one author, added before the first two merge, invites scrutiny of the
  language-eligibility case.
- The same effort spent on ideas 1 and 2 targets the two places we can lose: the base gap to
  Rust and Chapel (15–31% at 1T), and the wheel's margin on runner 74's AVX2 path.

Revisit after the PR merges, and only if the wheel's lead over C5 holds on the official runners.

## 7. Proposed additions to the HILL-CLIMB backlog

### Base (solution_2)

1. Vector dense kernel via lane-constant ORs (idea 1). Start from
   `prototypes/research/base_lane_dense.ispc`; sweep K = 1, 2 and targets `avx2-i32x8`,
   `avx2-i64x4`, `sse4-i32x4`; grep the asm for `vblendv` and `vpcmpeq` in `clear_dense` to
   catch failed folding. Predict +10–20% on Zen 3 and Zen 5.
2. Dense limit 128, 192, 256 after item 1 (idea 4). Predict +2–4%.
3. Next-prime scan by word (existing item 2; at most 3%).
4. Start-up autotune of the dense limit (idea 5), only if items 1–2 show the best limit differs
   between Zen 3 and Zen 5.

### Wheel (solution_1)

1. Remove masked tails on AVX2 (idea 2): pad `pw` to a multiple of 16 words, run lead-ins and
   tails unmasked. Predict +3–6% on Zen 3 at `avx2-i32x16`, flat on Zen 4/5 AVX-512.
2. One-member group fast path (idea 3; `prototypes/research/wheel_one_member.ispc`). Predict
   +3–4%.
3. Profile again with `wheel_phase_prof.ispc` on Zen 3 and Zen 5 after items 1–2, then decide
   on lead-in alignment (idea 6).
4. Existing item 3 (G sweep): drop 12 and 16; sweep 4, 6, 8, 10.
5. Arithmetic masks for some dense members (idea 7), only after items 1–3.
6. Drop existing item 8 (mod-210) to the bottom, for the reason in section 5.9.
