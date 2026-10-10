# Performance review: ISPC base and wheel entries

## Updated ranked suggestions (2026-10-10)

These supersede the priority order of the original review below. The newer profile says the
base sparse loop is identical to Rust's compiled loop (12 instructions per eight composites)
and apparently store-bound; the 422 KB dense code is much larger than Rust's 89 KB. The wheel
Zig port is 5–8% faster. The earlier suggestion to **raise the dense threshold** is withdrawn:
it was measured to lose 7%. Do not merge marks into wider base stores or segment the sieve.
The following whole-pass gains are hypotheses, not measurements or additive forecasts.

For every A/B test, verify prime counts and interleave at least five baseline/candidate runs
on the same host at both 1 thread and all hardware threads. Reject gains within A/A noise.
“Base: yes” below requires sequential odd-factor search, an individual source-level mark
for each composite, and a freshly allocated and initialized runtime-sized sieve each pass.
For the wheel-only ideas, “base: no” refers to the proposed wheel technique, not to whether
the wheel entry itself is faithful.

| Rank | Change | Target and rationale | Allowed for faithful base? | Expected gain; single A/B falsifier |
| --- | --- | --- | --- | --- |
| 1 | **Base:** Compare fresh allocation and zeroing strategies in `sieve_create`; still create and fully initialize an independent sieve every pass. | Setup and all-thread memory traffic could cost more than the marking-only profile indicates. | **Yes**, if runtime-sized and genuinely fresh per pass. | **0–5% all-thread**, uncertain; reject if setup cycles and all-thread throughput do not both improve. |
| 2 | **Base:** Reduce the 422 KB dense instruction footprint via inlining choices, out-of-line kernels, code layout or size-focused compilation of cold cases. | Dense front end and shared instruction resources under SMT; Rust's dense code is 89 KB. | **Yes**, if all odd-factor cases and individual marks remain. | **0–5% all-thread**; reject if hot code shrinks but I-cache behavior and throughput do not improve. |
| 3 | **Wheel:** Compare Zig and ISPC assembly for `sparse_prime`; isolate one addressing, spill, store-order or loop-control difference per experiment. | Sparse is about 52% of the wheel pass and Zig is 5–8% faster. | **No** for the eight-plane wheel representation as a base entry; **yes** for a fresh faithful wheel. | **1–5% wheel**; reject if the targeted assembly difference is absent or all-thread throughput stays flat. |
| 4 | **Base:** Test per-thread first-touch NUMA placement for newly allocated sieves, without retaining or sharing sieve contents. | Cross-node traffic with 192 workers; unlikely to affect 1 thread. | **Yes**, if each pass still creates and initializes its own buffer. | **0–5% all-thread**, host-dependent; reject if pages are already local or placement reduces throughput. |
| 5 | **Wheel:** In `apply_group`, generate an arithmetic mask for one pattern member instead of loading its word pattern; inspect spills. | Fused groups are about 35% of wheel time; trades pattern loads against ALU pressure. | **No** if used as fused multi-composite base marking; **yes** for wheel. | **0–3% wheel**; reject if reduced loads are offset by spills or ALU stalls. |
| 6 | **Base:** Place frequently executed dense cases together, with cold cases elsewhere, retaining full odd-factor dispatch. | Dense branch and I-cache locality, especially with SMT. | **Yes**; code layout changes neither discovery nor clearing. | **0–2%**; reject if counters and throughput do not move. |
| 7 | **Wheel:** Sweep fused-group widths near the existing per-target AVX-512 and AVX2 choices. | Fewer passes compete with spills and pattern-build work. | **No** for fused base marking; **yes** for wheel. | **0–3% wheel**; reject a 1-thread gain if all-thread throughput loses. |
| 8 | **Base:** Reschedule the eight individual byte ORs in `clear_sparse_e`, preserving increasing composite order and the pointer walk. | Sparse is about 61% of marking cycles, but matching Rust's store-bound loop suggests little headroom. | **Yes**; each composite still gets an individual byte OR. | **0–1%**; reject if the same 12-instruction kernel results or throughput is flat. |
| 9 | **Wheel:** Try limited software pipelining or stream reordering in `sparse_prime`, preserving the spill-free 64-bit indices. | Could hide sparse-store latency; extra registers may hurt SMT. | **No** in eight-plane form for base; **yes** for wheel. | **0–2% wheel**; reject on a new spill or all-thread regression. |
| 10 | **Base:** Compare SIMD shapes and the vector/scalar cutover **below 128**, confirming that lane conditions still fold to constants and retaining the NEON scalar route. | Dense is about 35% of the pass; could improve issue efficiency or footprint without raising the threshold. | **Yes**, with separate source-level marks for each composite. | **0–2%**; reject if code grows, runtime compares appear, or AVX2/NEON regresses. |
| 11 | **Wheel:** Profile per-pass pattern construction and scratch-space occupancy at all threads; try smaller per-pass scratch layout, not cached patterns between passes. | Workers' independent patterns may stress caches under load. | **No** for fused base patterns; **yes** for wheel with all state per pass. | **0–2% wheel**; reject if construction is negligible or scratch reduction does not improve all-thread throughput. |
| 12 | **Both:** Compare separately compiled CPU-specific variants selected before timing, with identical per-pass algorithm and honest output tags. | Avoid choosing Zen 5 settings for the AVX2 EPYC. | **Yes** for base variants preserving its marks and fresh passes; **yes** for faithful wheel variants. | **0–3% where currently mismatched**; reject if selection/binary footprint or either runner's all-thread throughput worsens. |

Rule basis: [`CONTRIBUTING.md`](CONTRIBUTING.md) requires an odd-by-odd next-factor search,
individual clearing in increasing `2 × factor` steps (lines 248–262), and a new runtime-sized
sieve instance each pass (lines 294–301). Compiler folding of separate single-bit source ORs
is the existing base approach, but a maintainer could still question it; do not handwrite
multi-composite base marks. Segmentation remains out of scope pending maintainer guidance.

## Original review (historical context)

Reviewed `hc/champion` (`5170556`) against the measurements in
[`STATUS.md`](https://github.com/cauldnz/Primes/blob/ispc-dev/ispc-dev/STATUS.md),
[`LEDGER.md`](https://github.com/cauldnz/Primes/blob/ispc-dev/ispc-dev/results/hc/LEDGER.md),
[`RESEARCH.md`](https://github.com/cauldnz/Primes/blob/ispc-dev/ispc-dev/RESEARCH.md) and
[`RULES-REVIEW.md`](https://github.com/cauldnz/Primes/blob/ispc-dev/ispc-dev/RULES-REVIEW.md).
Line references to ISPC below are to that champion revision; C++ and Rust references are to
the repository's existing rival entries. No experiments were run for this review. **All
prospective cycle savings are rough hypotheses, not benchmark results, and must not be added
together.**

## Baseline and constraints

At 10^6, the odds-only base sieve holds about 62.5 KB. On Zen 5, hc-010 measured approximately
38k cycles/pass in dense marking, 61k in sparse marking and 4k in next-prime search **for both**
the champion base and mike-barber's Rust entry. The final uninstrumented single-thread result
was 123.3k versus Rust's 125.3k passes; the ISPC base led at all threads. The wheel spends
about 52% of sampled time in sparse marking and 35% in fused groups. These are separate
measurements: phase-counter sums are not a complete accounting of timed-pass overhead.

All base proposals below retain one source-level single-bit operation per composite, an
odd-by-odd next-prime search, no prime knowledge beyond the evenness of 2, and no segmentation.
Every pass must allocate/initialize a fresh sieve; no prior-pass pattern of composite bits
can be reused. The wheel may fuse patterns, but must also sieve afresh. Check Zen 3/AVX2,
Zen 4 and 5/AVX-512, SSE4 Celeron and Pi 4/NEON separately: performance on one target is not
a portable win. In particular, hc-020 had to restore scalar dense marking on NEON.

## Five base-entry opportunities, in priority order

| Idea | Target, hypothetical Zen 5 saving | Base legality and evidence / uncertainty |
| --- | --- | --- |
| Inspect Zen 5 assembly for [`clear_sparse_e`](https://github.com/cauldnz/Primes/blob/hc/champion/PrimeISPC/solution_2/primes_base.ispc#L143-L169); try scheduling its eight independent byte updates to expose memory-level parallelism without a spill. | Sparse: **1–4k cycles/pass**. | Lines 158–159 perform eight distinct single-bit byte ORs; rearranging their scheduling does not combine composites. This is an instruction/port-pressure hypothesis, **not** evidence of a bottleneck: hc-003 already won 12.3% by walking a pointer, while hc-018's two-chunk unroll was flat or negative. |
| Sweep the dense/sparse cutover near [`DENSE_LIMIT 128`](https://github.com/cauldnz/Primes/blob/hc/champion/PrimeISPC/solution_2/primes_base.ispc#L57-L58), with a case for **every odd factor** newly made dense. Compare scalar and vector handling near [`clear_factor`](https://github.com/cauldnz/Primes/blob/hc/champion/PrimeISPC/solution_2/primes_base.ispc#L187-L206). | Boundary: **0–3k**. | No prime list is introduced and both routines still OR one bit per composite. **High uncertainty:** vector cases beyond 128 took over seven minutes to compile for one target; larger code may hurt I-cache and still lose to sparse marking. Rust uses dense through 129. |
| Sweep vector block shape and the scalar/vector cutover in [`clear_dense_vec`, lines 121–137](https://github.com/cauldnz/Primes/blob/hc/champion/PrimeISPC/solution_2/primes_base.ispc#L121-L137). Check that the lane comparisons actually fold into constant vector ORs rather than runtime compares/blends. | Dense: **0–2k**. | Line 132 remains one single-bit OR per composite in the source. hc-002 already brought dense to Rust's ~38k cycles, so the remaining headroom is small; wider gangs have previously failed mask folding. Retain the existing NEON scalar path at lines 185–193. |
| Check generated code for the fresh zeroing in [`sieve_create`, lines 71–79](https://github.com/cauldnz/Primes/blob/hc/champion/PrimeISPC/solution_2/primes_base.ispc#L71-L79); compare contiguous unmasked zeroing while retaining fresh allocation, full initialization and destruction **on each pass**. | Setup: **0–2k**, unprofiled. | This changes no sieve marking or discovery. The setup cost was not isolated by hc-010; a faster clear cannot be presumed. Never cache a marked sieve between passes. |
| Reduce per-factor byte-offset setup in [`clear_sparse_e`, lines 143–154](https://github.com/cauldnz/Primes/blob/hc/champion/PrimeISPC/solution_2/primes_base.ispc#L143-L154), retaining the existing eight `p mod 16` mask cases and the eight individual ORs. | Sparse setup: **0–1k**, speculative. | Offsets must come from the current discovered factor; a static prime table would not be base-legal. Specialization could increase dispatch or code size more than it saves. |

The next-prime scan is **not** a leading sixth idea: hc-009's word/`ctz` version lost
0.3% on Zen 3 and 1.4% on Zen 5. Likewise, L1 blocking of the dense phase needs a
separate rules review: a scheme that discovers primes in one segment and marks another
would violate the required non-segmented base algorithm.

## Three wheel-entry opportunities

1. **Sparse scheduling, not a repeat of hc-012.** [`sparse_prime`, lines 239–260](https://github.com/cauldnz/Primes/blob/hc/champion/PrimeISPC/solution_1/primes.ispc#L239-L260) advances eight independent plane indices; test instruction scheduling or limited software pipelining without increasing register spills. Hypothetical saving **1–3% of a pass**; uncertain. Preserve the 64-bit indices and the stream-0 loop bound at lines 243–255: hc-015's removal of a base-pointer spill produced +5–7% at 1T and 16T, whereas hc-012 regressed at 16T. The earlier byte-sparse variant in `RESEARCH.md` was 9% slower.
2. **Balance pattern loads against arithmetic.** In [`apply_group`, lines 176–213](https://github.com/cauldnz/Primes/blob/hc/champion/PrimeISPC/solution_1/primes.ispc#L176-L213), trial-generate masks for one or two members arithmetically instead of loading every member's pattern. Potential **0–3% of a pass**, with substantial uncertainty about ALU/load pressure and register allocation. Keep the existing no-lead-in starts at lines 178–193 (hc-016) and lone-13 fast path at lines 221–225 (hc-004); both are measured wins.
3. **Target-specific fused-group width.** Benchmark small group sizes around [`G=6` on AVX-512 and `G=8` otherwise](https://github.com/cauldnz/Primes/blob/hc/champion/PrimeISPC/solution_1/primes.ispc#L45-L52); consider start-up selection among compiled variants only if it demonstrably helps unknown machines. Potential **0–2% further**, uncertain. hc-011's G=6 gave +4.5% at Zen 5 1T but −1.2% at Zen 3 1T; the current target-specific choice has already captured that obvious split. Bigger groups can spill registers. AVX2-only unmasked tails are already target-gated at lines 54–61, so do not propose enabling overruns unconditionally on AVX-512.

## Rust entry, same base algorithm

- The strongest analogous experiment is a pointer-walk version of
  [`ResetterSparseU8::reset_sparse`, lines 247–292](https://github.com/cauldnz/Primes/blob/ispc-dev/PrimeRust/solution_1/prime-sieve-rust/src/unrolled.rs#L247-L292).
  Preserve all eight byte ORs and the fresh per-pass sieve; reduce chunk-address arithmetic,
  then examine assembly and benchmark. A **1–4k-cycle** saving is conceivable but unmeasured
  in Rust.
- [`extreme_reset_word`, lines 238–250](https://github.com/cauldnz/Primes/blob/ispc-dev/PrimeRust/solution_1/helper-macros/src/lib.rs#L238-L250)
  constructs `TokenStream::default()` for a word with no hits but fails to return it. Thus
  empty words still get loads and stores. Fixing the apparent mistake might **slow** the
  dense phase by removing LLVM's contiguous vectorization; test generated code and timings
  before accepting it. There is no demonstrated positive cycle estimate.
- Benchmark dense cutovers around the current 129
  ([`unrolled_extreme.rs`, lines 29–55](https://github.com/cauldnz/Primes/blob/ispc-dev/PrimeRust/solution_1/prime-sieve-rust/src/unrolled_extreme.rs#L29-L55))
  and a Zen 5-specific build with and without AVX-512F. The current
  [Linux rustflags disable AVX-512F](https://github.com/cauldnz/Primes/blob/ispc-dev/PrimeRust/solution_1/.cargo/config#L3-L10)
  because it hurt newer Skylake Xeons; that is not proof of a Zen 5 regression or of a gain.
  Keep every odd dense factor, not just known primes.

## Rule-risk review

No definite faithfulness violation is established. The base vector route's most reviewable
line is:

> `x |= ((t >> 6) == k) ? ((uniform uint64)1) << (t & 63) : 0;   // one composite`

([`clear_dense_vec`, line 132](https://github.com/cauldnz/Primes/blob/hc/champion/PrimeISPC/solution_2/primes_base.ispc#L132)).
Line 134 stores the vector of resulting words. A strict reader could object that codegen
merges writes for multiple composites; the source still has a separate single-bit OR for
each hit, the same distinction made for Rust's generated code in `RULES-REVIEW.md`.
Document that distinction rather than changing the source to multi-bit mask ORs.

Dense marking starts at the **chunk containing** p² rather than precisely at p²:

> `clear_dense_from(w, nwords, P, ((P * P / 2) / 64 / P) * P);`

([line 112](https://github.com/cauldnz/Primes/blob/hc/champion/PrimeISPC/solution_2/primes_base.ispc#L112);
the vector path uses the same calculation at line 122). It may re-mark earlier
composites and p itself, which is restored at
[`clear_dense_from`, lines 107–108](https://github.com/cauldnz/Primes/blob/hc/champion/PrimeISPC/solution_2/primes_base.ispc#L107-L108).
This is defensible but should be explained if a reviewer reads “from p²” literally.
The wheel's fixed mod-30 residues and runtime-generated 7·11 tile do not invoke the
**base-only** prohibition on prior knowledge of primes beyond 2.

## davepl's `PrimeCPP/solution_5`

[`mark_multiples_impl`, lines 254–314](https://github.com/cauldnz/Primes/blob/ispc-dev/PrimeCPP/solution_5/PrimeCPP_array.cpp#L254-L314)
uses an eight-hit byte loop for large factors, like the base entry's sparse routine. For
smaller steps it builds `stepMasks`, `cycleMasks` and `blockMasks`, then processes consecutive
64-bit words using AVX-512, AVX2, SSE2 or NEON
([lines 316–577](https://github.com/cauldnz/Primes/blob/ispc-dev/PrimeCPP/solution_5/PrimeCPP_array.cpp#L316-L577)).
The configurable wordwise threshold defaults to 64
([lines 47–53](https://github.com/cauldnz/Primes/blob/ispc-dev/PrimeCPP/solution_5/PrimeCPP_array.cpp#L47-L53)).
Its first factor uses overwrite rather than read-modify-write on the empty sieve
([lines 688–708](https://github.com/cauldnz/Primes/blob/ispc-dev/PrimeCPP/solution_5/PrimeCPP_array.cpp#L688-L708));
its prime scan uses word inversion and `ctz`
([lines 189–225](https://github.com/cauldnz/Primes/blob/ispc-dev/PrimeCPP/solution_5/PrimeCPP_array.cpp#L189-L225)).

The transferable ideas are measuring architecture-specific cutovers, keeping sparse
addresses cheap, and inspecting codegen. **Do not transplant its precombined word-mask
updates into the base source**: a single such OR/overwrite may mark several composites,
contrary to the stipulated one-operation-per-composite rule. The wheel may use fused masks.
Its `ctz` scan has already been tried for the base entry (hc-009) and lost.
