# Research notes 2: the base table, davepl's entry, and what is left for the base entries

Written 2026-10-09 by research agent 2 for the hill-climbing run. It covers the official base
table, davepl's `PrimeCPP/solution_5`, ranked ideas for our base entry (`PrimeISPC/solution_2`
on `hc/champion`) and for mike-barber's Rust (`PrimeRust/solution_1`), and the Zig entries.

Local evidence comes from the shared 4-vCPU Intel Xeon sandbox (48KB L1d per core, AVX-512).
Pass counts there swing by 6% to 10% between runs of one binary, so I lean on instruction
counts (valgrind/callgrind, deterministic) and assembly instead. perf has no hardware counters
here. Nothing in this note ran on Zen. Scratch work is in `/tmp/claude-0/research2/` and will
not survive the session; the parts worth keeping are quoted below.

## 1. Summary

- The Rust entry already tops the faithful 1-bit base table on all five daily runners, in every
  cell but one: Threadripper 1T, where a Swift entry leads it by 3.4% (122,869 against
  118,846). davepl_array_optimized reports only an all-threads line and ranks fifth there,
  21% behind Rust's 96-thread line. Details in `results/leaderboard-2026-10-09b.md`.
- New finding: in the champion base entry every dense vector load and store is masked. The AVX2
  build has 13,924 `vmaskmovpd`, the AVX-512 build 13,922 k-masked moves and the SSE4 build 856
  load-blend-store sequences, all in the hot dense loops. `clear_factor` runs under an execution
  mask ISPC can't prove is all on. One `unmasked { }` block removes all but four. It also
  explains hc-020: with the block in place, ISPC's NEON target emits clean `ldp`/`orr`/`stp` for
  the vector dense code, without any per-lane stores.
- The dense phase pays about 30% of its cost for not fitting in L1: on the sandbox it costs about
  7 cycles a word (all 29 vector primes; 6.6 to 9.2 across runs) when the array fits in L1,
  against 10.0 to 10.4 at the real 62.5KB. The rules close the two ways to recover that: blocking across primes is the
  segmentation GordonBGood says is refused, and alternating sweep direction breaks "increasing
  the number with 2 * factor".
- Rust 1.57 (the Docker image) and current Rust 1.97 differ in a way that matters: 1.97 halves
  the dense code for small factors but turns the sparse loop from 12 instructions per eight ORs
  into 19. A five-line pointer walk fixes it (11). Per pass: 466k instructions (1.57), 594k
  (1.97), 460k (1.97 with the pointer walk).
- Alpine 3.21's community repo packages Zig 0.13.0 and ISPC 1.25.3. Alpine 3.22 has ISPC 1.26.0
  and Ubuntu 26.04 has 1.28.2. `RULES-REVIEW.md` says ISPC is "Alpine only in edge"; that is out
  of date.

## 2. The official table (task a)

Full tables per runner are in `results/leaderboard-2026-10-09b.md`. Best lines, faithful
1-bit base:

| Runner | 1T leader | Rust 1T | best GordonBGood 1T | MT leader | davepl_array_optimized |
|---|---|---|---|---|---|
| 73 Threadripper 9995WX | Swift 122,869 | 118,846 (2nd) | Chapel 117,862 (4th) | Rust 6.83M @96 | 5.40M @192, 5th |
| 74 EPYC VM (AVX2) | Rust 63,144 | 1st | Nim 52,401 (4th) | Rust 2.99M @128 | 2.49M @128, 5th |
| 18 i7-9750H | Rust 55,007 | 1st | Nim 53,298 (3rd) | Rust 267k @6 | 209k @12, 5th |
| 24 Celeron 3865U | Rust 20,091 | 1st | Nim 19,163 (3rd) | Rust 40.5k @2 | 31.6k @2, 7th |
| 36 Pi 4 | Rust 9,674 | 1st | Nim 9,183 (3rd) | Rust 17.6k @4 | 17.5k @4, 3rd |

What this means for the goal:

- "Top faithful 1-bit base entry" is already Rust's everywhere except Threadripper 1T. Either
  entry needs about +4% at 1T on Zen 5 to take that cell from Swift.
- davepl's entry doesn't threaten either of ours on these numbers. If Chris saw it on top,
  the view was filtered by thread count or showed an older session; worth asking which filter
  he used.
- Our base entry, from the Azure ratios, would lead 1T on the EPYC VM if its host is Zen 3 or
  Zen 4 (+5% to +7% over Rust), tie Rust on the Threadripper, and trail Rust and Nim on the Pi.
  We have no Intel or SSE4-only data for the i7 and Celeron runners.
- The Rust entry runs at 96 and 192 threads on the Threadripper and its 96-thread line is the
  better one (6.83M against 6.67M). We print all, half and a quarter of the hardware threads, so
  we also get a 96-thread line.

## 3. davepl's `PrimeCPP/solution_5` (task b)

Source: `PrimeCPP_array.cpp` (981 lines, "developed with assistance of ChatGPT-5"),
`Dockerfile`, `benchmark.sh`.

What it does:

- Storage: one bit per odd number in a `uint8_t` array, `posix_memalign` to 64 bytes, then
  `memset` to zero, every pass. Inverted logic (set bit = composite).
- Next prime: a 64-bit word scan with `__builtin_ctzll` (`find_next_prime_bit`).
- Factors below 64 (`BITSTEP_WORDWISE_THRESHOLD`): per factor it builds `stepMasks[first]`,
  a 64-bit mask holding every multiple in a word for each start phase, then a cycle of p word
  masks repeated into a 64-word `blockMasks` table. It ORs that table into the sieve with
  512-bit, 256-bit or 128-bit vectors (`_mm512_or_si512` on the Threadripper, NEON `vorrq_u64` on
  the Pi). One OR sets every multiple of p in eight words at once.
- The first prime (3) uses `Overwrite`: plain stores of the mask instead of load-OR-store. The
  constructor's `memset` still runs, so this saves the reads of the factor-3 sweep only.
- Factors from 64 up: eight byte ORs per group of 8p bits, offsets and masks in small runtime
  arrays, `ptr += bitStep`. This is the same loop as ours and Rust's, with the masks in registers
  instead of immediates, so no switch on p mod 16.
- Threads: one `std::thread` per hardware thread, a relaxed atomic stop flag, passes summed.
  Only one result line, at `hardware_concurrency()` threads. No 1T line.
- Build: Ubuntu 22.04, clang 14, `-march=native -mtune=native -O3 -ffast-math -flto`. On the
  Threadripper `-march=native` turns on AVX-512; on the EPYC VM it gets AVX2.

What differs from ours and Rust's, and whether we could use it:

| Technique | Ours / Rust | Base-legal for us? |
|---|---|---|
| Multi-bit word masks for factors < 64 | one single-bit OR per composite in the source, merged by LLVM | No. GordonBGood's README: entries that "cleared all the dense composites in the word with a single instruction using a mask" were "correctly" refused as base. davepl's entry is tagged base anyway; we can't cite it. |
| Overwrite for the first prime | load, OR, store | Probably yes, if written as single-bit ORs into a register that starts at zero and replaces the zeroing pass (idea B3). Precedent: the original author's own entry. |
| Dense threshold 64 | 128 (ours), 129 (Rust) | Legal, but slower: hc-017 and Rust's results favour higher limits. |
| ctz word scan | bit-by-bit scan | Legal (still checks odd numbers in order). hc-009 measured it 0.3% to 1.4% slower for us. |
| Runtime masks in the sparse loop | constant masks via an 8-way switch | Legal. Costs registers; our loop already uses 10. |
| All-threads line only | 1T plus several thread counts | Legal, but it forfeits the 1T table. |

So the one large difference from our entry and Rust's is the multi-bit masks, which the base
rules (as GordonBGood and RULES-REVIEW read them) forbid us. Even with them, his entry trails
Rust's best multi-thread line by 17% to 21% on the two Zen runners.

## 4. Base entry: where the cycles go and what the rules leave (task c)

### Per-pass work at 10^6

- 30 dense primes (3 to 127), each sweeping the 7,813-word (62.5KB) array: 234k word updates
  and 3.75MB of L1 fill plus writeback per pass. The start at the chunk holding p² wastes only
  1,070 words in total, under 0.5%.
- 137 sparse primes (131 to 997): 133.5k byte ORs. The 66 below 512 touch every cache line.
- Zen 5 split (hc-010, TSC): dense 38k, sparse 61k, scan 4k cycles.

### Bounds

- Sparse: 133.5k ORs in 61k TSC cycles is 0.46 TSC cycles per OR. With the core clocking about
  1.5 times the 2.6GHz TSC, that is roughly 1.45 ORs per core cycle against Zen 5's limit of two
  stores per cycle. At most about 25% headroom remains, and hc-018 (two chunks per trip) found
  none of it.
- Dense: at hc-010 our code and Rust's cost the same 38k on Zen 5, although they stop
  vectorising at different factors (ours at 117, Rust's at 83; see section 5) and our loops ran
  through masked moves (B1). Adding the AVX-512 target afterwards (hc-013) gained only 1%. Equal
  cost from different code points to a memory bound, not an instruction bound.
- Measured here (`/tmp/claude-0/research2/densebench`, champion `clear_dense_vec` for the 29
  vector primes, avx2-i32x8, five sweeps on two cores):

  | array | cycles per word, all 29 primes |
  |---|---|
  | 15.6KB | 7.6–8.3 |
  | 31.2KB | 6.6–9.2 |
  | 43.0KB | 6.9–8.8 |
  | 61.0KB (the real sieve) | 10.0–10.4 |
  | 122KB | 10.2–10.9 |

  The step sits at the 48KB L1. On this core about 30% of the dense phase is the cost of
  streaming the array from L2 for every prime. On Zen 3 and Zen 4 (32KB L1) the share is
  probably larger. That 30% is about 11k of the 38k dense cycles on Zen 5, or roughly 10% of a
  pass.

### What the rules allow on the cache problem

- Blocking the dense phase across primes (all dense primes over a 16KB block, then the next
  block): not base-legal. It needs the dense primes before their clearing is finished, which is
  "determining all base prime values as a separate process" (GordonBGood, Chapel README). Rust's
  and GordonBGood's `block16K` variants block within one prime only, which can't help a dense
  sweep.
- Alternating sweep direction (forward for one prime, backward for the next, so each sweep
  starts on the lines the last one left in L1): the order is invisible in the result, but the
  rule text says "increasing the number with 2 * factor on each cycle". Not legal as written. It
  would be worth about the same 10%. I would not ask the maintainers before the PR merges.
- Handling two primes in one sweep: the same deferred-clearing problem as blocking. Not legal.

So the cache cost is the price of the rules, and the remaining legal levers are smaller.

### Ranked ideas for the base entry

Gains are per pass at 1T unless stated. Cycle figures are Zen 5 TSC cycles out of a 103k pass.

**B1. `unmasked` in `clear_factor` (all phases that use vectors; mostly dense).**
- Evidence: the champion's dense loops load and store through masks. Counts in the assembly:
  13,924 `vmaskmovpd` (avx2-i32x8), 13,922 k-masked `vmovdqu64` (avx512skx-x8), 856 SSE4
  load-blend-store sequences. A loop scan shows every large dense loop (`.LBB108_37` onwards in
  the AVX2 asm) uses only masked moves. With the patch below: 4, 2 and 0. The self-test passes
  on the AVX-512 dispatch, a forced avx2-i32x8 build and a forced sse4-i32x4 build (13 of 13).
- Why it happens: `clear_factor` is a non-inlined `static` function, so ISPC compiles it with an
  unknown entry mask; `worker`'s `unmasked` block doesn't reach into callees. RESEARCH.md
  section 4 already warns about this for prototypes.
- Expected gain: AVX2 and SSE4 machines first (Zen 3, runner 74, the i7, the Celeron). The wheel's
  hc-007, which removed far fewer masked stores, gained 3.7% on Zen 3 and 5.3% on AVX2-only
  Zen 4. I would predict +2% to +8% on AVX2 Zen and 0% to +2% on Zen 5 with AVX-512, where
  k-masked stores are cheap. A caution on size: RESEARCH.md cites uops.info at one masked
  256-bit store per 6 cycles on Zen 2 to Zen 4, but 56.6k of them per pass at that rate would
  exceed the whole Zen 3 pass (about 300k cycles), so the real cost on Zen 3 must be nearer
  two cycles. Local timing on the Intel sandbox was inconclusive (five rounds, ±10%), as
  expected, since Intel's masked stores are cheap.
- Effort: an hour plus Zen 3, AVX2-only Zen 4, Zen 5 and Cobalt 100 runs.
- Rules risk: none. Same source, same ORs.

```diff
 static void clear_factor(uniform Sieve * uniform s, uniform int p) {
     if (p >= DENSE_LIMIT) { clear_sparse(s, p); return; }
+    unmasked {    // always called with every lane on; without this, every vector load and store is masked
     switch (p) {
 ...
         D(123) D(125) D(127)
     }
+    }
 }
```

**B2. Vector dense on NEON, after B1 (dense, arm64 only).**
- Evidence: with B1 and the `ISPC_TARGET_NEON` guard removed, `neon-i32x4` and `neon-i32x8`
  compile the dense loops to `ldp q`/`orr v`/`stp q` with no `st1 {v.d}[n]` lane stores (0 of
  them, against 56 lane stores and 244 `tbz` mask tests in a single dense loop without B1). hc-020's
  diagnosis ("ISPC's NEON target scalarises the vector form") was the execution mask, not NEON.
- Expected gain: Cobalt 100 and the Pi 4. On x86 the vector dense change gained 22% to 24%;
  on NEON the vectors are 128 bits, so I'd predict +8% to +15% on Cobalt 100, enough to pass
  Rust's 4.3% lead there. Also try `neon-i32x8` for the base entry, which gained 15% for the
  wheel on Cobalt 100.
- Effort: two hours plus a Cobalt 100 run. Compile time for the NEON vector build was 37s.
- Rules risk: none.

**B3. Zeroing folded into the factor-3 sweep (set-up and dense).**
- Change: for p = 3 only, start each word at zero instead of loading it (`uint64 x = 0;` then
  the same single-bit ORs, then the store), and drop the `foreach` zeroing in `sieve_create`.
  Words the factor-3 routine doesn't reach (none at 10^6, but small sizes in the self-test) must
  still be zeroed.
- Evidence: callgrind shows the zeroing as a 62.5KB `rep stosb` each pass (LLVM turns the
  `foreach` into `memset`). davepl's entry skips the factor-3 reads the same way, though it
  still memsets.
- Expected gain: the zeroing pass (about 1k cycles) plus the read half of one of 30 dense sweeps
  (about 0.6k): 1.5% to 2.5%.
- Effort: half a day, with self-test sizes 1 to 127 checked.
- Rules risk: low. Every composite still has its own OR; the buffer is still allocated and
  initialised every pass. State it in the README.

**B4. Direct dispatch for the dense range (scan and dispatch).**
- Change: for factors below 128, replace the scan loop and the 63-way `switch` with a straight
  sequence: `if (!is_composite(1)) clear<3>; if (!is_composite(2)) clear<5>; ...` up to 127,
  then the existing loop from 129. That still checks every odd number in order, as the rule asks.
- Reasoning: the scan costs 4k cycles (4%) on Zen 5 for about 500 bit tests, which points to
  branch mispredicts at the loop exit and the indirect jump, once per prime. 30 of the 168
  primes are dense.
- Expected gain: 0.5% to 2%. Effort: two hours. Rules risk: none.

**B5. Newer ISPC (compiler lever; all phases).**
- Evidence: ISPC 1.28.2 (LLVM 20.1) builds the same source, passes the self-test and cuts the
  AVX2 dense instructions from 233k to 178k a pass (callgrind, −24%); sparse is unchanged (216k
  against 213k). It does not fix the x16 folding (61,270 `vpcmpeq` and 122,480 `vblendv` in
  avx2-i32x16 with either compiler), and compile times are similar (24s against 18s for
  avx2-i32x8). The 1.28.2 build exited 1 under valgrind in its multi-thread run once out of two;
  three native runs were clean. I'd treat that as a valgrind artefact, but check it.
- Packaging: Ubuntu 26.04 (`resolute`, LTS since April 2026) ships ispc 1.28.2-1; Alpine 3.22
  ships 1.26.0 and Alpine 3.21 1.25.3 (linked against LLVM 19.1), for x86_64 and aarch64.
  CONTRIBUTING lists Alpine before Ubuntu. Moving the image is a Dockerfile change, but it needs
  the full machine set again.
- Expected gain: 0% to 4% on AVX2 machines, less where dense is memory-bound. Effort: half a day
  plus a full scoreboard run. Rules risk: none.

**B6. Vector form for factor 127 (dense).** 127 is the only dense prime still on the scalar
routine (`VEC_LIMIT` 119): about 3,900 scalar ORs against about 1,000 512-bit updates. Worth
about 1k cycles, 1%. Splitting the unrolled block in two may stay under LLVM's unroll limit.
Effort: two hours. Rules risk: none.

**B7. Dense limit about 160 (dense against sparse).** A sparse prime costs about 0.46 TSC cycles
per OR, so p = 131 costs about 1.7k and p = 167 about 1.4k, against about 1.3k for a vector dense
sweep. Moving 131 to 157 (six primes) saves perhaps 1k to 2k cycles, 1% to 2%, if B6's compile
fix works. hc-017's wheel result (lowering the limit lost 1%) is a different trade. Effort: half
a day. Rules risk: none.

**B8. Thread placement for the half-thread line (multi-thread).** On the Threadripper, Rust's
96-thread line beats its 192-thread line by 2.4%; SMT adds nothing for this workload. Pinning the
half-thread run one per core (`pthread_setaffinity_np`, siblings from
`/sys/devices/system/cpu/cpu*/topology/thread_siblings_list`) guards against the scheduler
stacking two threads on one core. Expected 0% to 3% on that line only. Effort: half a day.
Rules risk: none, but Docker cpusets and VMs make it easy to get wrong.

Tried already and not worth repeating: word scan with ctz (hc-009), two chunks per sparse trip
(hc-018), `avx2-i32x16` / `avx512skx-x16` (masks don't fold).

Sparse-loop ideas I considered and set aside:

- Starting the sparse loop at p²'s byte rather than its chunk (as Swift does) saves at most seven
  ORs per prime: about 0.2%.
- Masks in registers instead of the 8-way switch (as davepl does) needs eight more registers than
  the loop has.
- Any loop that clears two primes at once is deferred clearing, as above.

## 5. Rust: `PrimeRust/solution_1` (task d)

Built locally from a copy (`/tmp/claude-0/research2/rust`), `cargo build --release`, with the
repo's `.cargo/config` (`target-cpu=native`, `-avx512f`). Three toolchains: Rust 1.57 (the
Docker image's), 1.97 (current), and 1.97 without `-avx512f`.

Instructions per pass at 1T, `--bits-extreme`, callgrind (AVX2 path; memset counted as one
instruction per byte by valgrind):

| build | total | sparse, scan and driver (`run_implementation_st`) | memset |
|---|---|---|---|
| Rust 1.57 | 466k | 220k | 62k |
| Rust 1.97 | 594k | 342k | 62k |
| Rust 1.97, pointer-walk sparse loop | 460k | 207k | 62k |
| our base, ISPC 1.22, avx2-i32x8 | 518k | 213k (sparse) + 9k | 62k |

Codegen notes:

- Rust 1.57 sparse loop: 8 `orb` + `add` + `sub` + `cmp` + `jae` = 12 instructions per eight ORs.
  Rust 1.97: LLVM's loop strength reduction gives each of the eight offsets its own pointer, so 8
  `orb` + 8 `add` + `sub` + `cmp` + `jb` = 19.
- Dense: both versions vectorise up to factor 83 (SLP, 256-bit) and leave 85 to 129 scalar;
  1.57 also leaves factor 3 scalar. Rust 1.97 halves the factor-3 routine (5.9k against 10.4k
  instructions a pass).
- Local timing of 1.57 against 1.97 and the AVX-512 build: three interleaved rounds, all within
  the 6% noise (40.7k to 46.7k). No conclusion from timing.

Ranked changes, none of which change the algorithm:

**R1. Pointer-walk sparse loop.** Replace the `chunks_exact_mut` loop in
`ResetterSparseU8::reset_sparse` with one raw pointer stepped by `skip` and eight fixed offsets
(`*ptr.add(o0) |= m[0]` …). Tested: 11 instructions per eight ORs under 1.97, unit tests pass
(22 of 22), 78,498 primes. Gain: about 1% under 1.57 (12 to 11 instructions); under a newer
image it is what keeps the sparse loop from regressing by 7 instructions per eight ORs. Our
hc-003, which took the ISPC loop from 27 to 11, gained 12% on Zen 5, so sparse instruction count
matters there. Effort: an hour.

**R2. Newer Rust image, together with R1.** `rust:1.57` is LLVM 13, which predates Zen 4 and
Zen 5 tuning, and the runtime image is Debian buster (end of life). A current image plus R1
gives the fewest instructions of any build (460k a pass) and the better dense code. Without R1
it is worse (594k). Gain: 0% to 3% at 1T, unmeasured on Zen. CONTRIBUTING only merges changes
that "objectively improve the performance", so this needs Zen 5 numbers in the PR.

**R3. Allow AVX-512.** The `-avx512f` flag guards against Skylake-X clock drops. The
Threadripper is the only daily runner with AVX-512 and runs it at full width; the EPYC VM, i7,
Celeron and Pi lack it, so they are unaffected. With AVX-512 on, LLVM uses zmm for some dense
routines (factor 5: 6 zmm instructions). Our hc-013 (an AVX-512 target for the base entry)
gained 1.0% at 1T on Zen 5. Expect 0% to 2% on runner 73 only. Effort: a one-line change, then a
Zen 5 run.

Lower down:

- Dense limit 129: LLVM leaves 85 to 129 scalar. If dense is memory-bound (section 4), raising
  the limit or vectorising 85 to 129 by hand gains little; hc-001 measured Rust's dense cost as a
  flat 2.7k cycles per factor on Zen 4, which fits that.
- Threads: `get_auto_threads_list` already gives 1, 4, n/2 and n; n/2 is the best line on the
  Threadripper. Nothing to gain.
- Zeroing: `vec![0; n]` becomes `calloc` and a 62.5KB memset each pass. B3's trick applies to
  Rust too, but the macro-generated dense code would need a second "first factor" variant.

Before any PR on `PrimeRust/solution_1`: check for an open PR on that solution (CONTRIBUTING
step 2). This session couldn't reach the upstream API to check.

## 6. Zig (task e)

- `solution_1` (devblok) and `solution_2` (ManDeJan) are 8-bit entries; only solution_2 appears
  on the runners, as two unfaithful lines (25.6k and 15.0k on the Threadripper).
- `solution_3` (ManDeJan, ityonemo, SpexGuy) is the interesting one but has no results in
  today's sessions. Its Dockerfile downloads Zig 0.8.0 from ziglang.org at build time.
  Techniques that matter for a fast faithful base or wheel entry:
  - Comptime-generated dense functions per factor (`unrolled.zig`, `DenseFnFactory`) that load
    `@Vector` chunks, set single bits and store: the same idea as our vector dense, written with
    explicit vectors instead of relying on lane folding.
  - Sparse functions from a lookup table indexed by the start phase ("progressive shift"), like
    Rust's `pattern_equivalent_skip`.
  - A page-aligned `calloc` allocator, and a `NonClearing` allocator combined with inverted
    logic (`PRIME = 1`), aimed at the same zeroing cost as B3.
  - Two thread models: "Amdahl" (threads share one sieve, split by factor) and "Gustafson" (one
    sieve per thread, as ours), plus `-no-ht` variants that use physical cores only.
  - A wheel whose patterns are computed at compile time. That would fail the faithfulness rule
    for us; our wheel builds its tile at run time.
- Alpine 3.21 community packages zig 0.13.0-r1 (x86_64 and aarch64); Alpine 3.22 has 0.14.1-r0.
  Reusing solution_3's code would mean porting it from Zig 0.8.0 to 0.13 or later; its
  `comptime const` declarations, for one, are rejected by current compilers.

## 7. Proposed hill-climb queue (base and Rust)

1. hc: B1 (`unmasked` in `clear_factor`). Zen 3, AVX2-only Zen 4, Zen 5, Cobalt 100. Predict
   +2% to +8% on AVX2 Zen, 0% to +2% on Zen 5, unchanged on Cobalt 100 (scalar there until B2).
2. hc: B2 on top of B1, NEON only, `neon-i32x4` and `neon-i32x8`. Predict +8% to +15% on
   Cobalt 100.
3. hc: B3 (zeroing folded into factor 3). Predict +1.5% to +2.5% everywhere.
4. hc: B4 (direct dense dispatch). Predict +0.5% to +2%.
5. Rust R1 and R3 on a copy, against the upstream build, Zen 3 and Zen 5, both images (1.57 and
   current). Predict R1 +0% to +2% under 1.57; R3 +0% to +2% on Zen 5 only.
6. Measurement, not a change: profile the Swift entry against Rust on Zen 5 (TSC phases). It is
   the only entry ahead of Rust anywhere, and only on Zen 5; knowing which phase it wins tells us
   where the last 4% on the Threadripper is.
7. Correct `RULES-REVIEW.md`: ISPC is packaged in Alpine 3.21 and 3.22 community, not only edge.

## Sources

- PrimeView API, sessions 9733 to 9746, pulled 2026-10-09.
- `PrimeCPP/solution_5/PrimeCPP_array.cpp`, `Dockerfile`, `benchmark.sh`.
- `PrimeRust/solution_1` (`helper-macros/src/lib.rs`, `unrolled.rs`, `unrolled_extreme.rs`,
  `.cargo/config`, `Dockerfile`).
- `PrimeSwift/solution_1/PrimeSwift_1bitStriped_u8/Tools/PrimeSieve.swift.in`.
- `PrimeChapel/solution_1/README.md` (base-rule notes on masks and segmentation).
- `PrimeZig/solution_3/README.md`, `src/unrolled.zig`, `src/alloc.zig`, `src/main.zig`.
- Alpine APKINDEX for v3.21 and v3.22 community (x86_64, aarch64); packages.ubuntu.com for
  noble, questing and resolute.
- ISPC 1.28.2 release tarball from GitHub, used for local tests only.
