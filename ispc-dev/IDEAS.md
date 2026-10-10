# Idea queue for the climber (workshop research, 2026-10-10 17:00; outside reviews merged 17:45)

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

## Merged 17:45 from three outside reviews (GPT-6, Grok 4.7, Gemini), vetted by the workshop

The reviews were run outside this repo; the workshop checked each idea against the ledger, the
base rules and the profile. Their gain estimates are guesses (Gemini's 12-25% claims especially);
predict your own. Source in brackets.

**Raise the priority of, in this order:**
- **Item 1 (thread count from the affinity mask) and item 2 (pinning) together, on the 64- or
  96-vCPU node, pinned against unpinned at threads = vCPUs and at half.** If pinning closes the
  gap, the 14% lead is placement, not the sieve. [Grok, Gemini, workshop]
- **Item 4 (one clock reader, a relaxed atomic stop flag)** at full occupancy only: at 128-192
  threads every worker calls `clock_gettime` every pass. [Grok, GPT]
- **Item 18 (AVX-512 off) measured at threads = vCPUs.** The EPYC runner is AVX2-only, so this
  also tells us whether our Zen 5 all-threads lead depends on a target that runner lacks. [Grok]

**New ideas:**
20. **glibc arena count**: `mallopt(M_ARENA_MAX, nthreads)` before creating threads (or the
    opposite), still `aligned_alloc`/`free` every pass. Probe at full occupancy; flat means stop.
    Base: yes. A buffer recycled across passes is **not** faithful: probe only, never ship. [Grok]
21. **Software prefetch** a few chunks ahead in the sparse loop, for large factors, at full
    occupancy only (two sieves per core exceed the 48 KB L1D). Base: yes (a hint, no state).
    Expect a 1T loss. [Gemini]
22. **Wheel sparse: a pointer and a mask per plane**, pointer stepped by `p >> 6`, mask rotated by
    `p & 63` with the rotate specialised into immediates; not Zig's counted unroll-4 (hc-043
    lost). Wheel only. Measure at all threads; revert on any spill. [Grok]
23. **Wheel groups: generate one member's mask arithmetically** instead of loading its pattern,
    in `apply_group`. Trades loads for ALU; check spills. Wheel only. [GPT]
24. **First-touch placement** of each new sieve on its worker's core (allocate and initialise in
    the worker, which we already do; confirm with the 128-thread node). Base: yes. [GPT]
25. **Rust comparator note:** mike-barber's `extreme_reset_word` (`helper-macros/src/lib.rs`)
    builds an empty `TokenStream` for words with no hits but doesn't return it, so empty words
    still get loads and stores. Fixing it may *slow* the dense phase (it may be what lets LLVM
    vectorise). Record it in the Rust base delta; don't change mike-barber's entry. [GPT]

**Already tried; skip unless the profile changes:** sparse immediate offsets (hc-032, flat),
16-composite sparse unroll (hc-018, flat), word `tzcnt` scan (hc-009, lost), raising or lowering
the dense limit (hc-031, hc-036), 64-byte alignment (done), inverted logic (we already OR into
a zeroed buffer), AVX-512 wheel streaming (already a target), group-width sweeps (hc-011,
hc-014), shared pass counters (we have none).

**Not allowed or grey; don't build:** interleaving two factors in the sparse loop (grey: the
rules clear one factor's multiples at a time) [Gemini]; a thread-local bump arena that hands the
same pages back every pass (state across passes) [Gemini]; huge pages beyond the sieve's own
size [Grok]; segmentation (item 10: unblocked by Chris on 2026-10-11 as F2, on `hc/champion-grey` only; see RUN-PLAN.md).

## Fable ideation pass (workshop, 2026-10-10 19:10)

Grounded in: the 96-vCPU phase profile (1/24/48/96 threads), the sparse-loop assembly
side-by-side, the champion base compiled here (`avx512skx-x8`), the wheel's compiled sparse
loop, the rules text, and an LRU simulation. Tag these [Fable] in the ledger.

**The diagnosis that the ideas hang off.** The 62.5 KB sieve doesn't fit Zen 5's 48 KB L1D, and
every phase sweeps it top to bottom. Under LRU a monotone sweep of a working set larger than the
cache hits 0% (simulated: 0% for 977 lines through 768 line slots). So every dense sweep (31 per
pass) and every sparse line touch (about 100k per pass, 0.8 per composite) is an L2 fill plus a
writeback. Sparse at 1T: about 0.65 core cycles per composite against a 0.5 store-port floor;
the rest is L2 traffic. Under SMT the two sieves share one L2 port, so sparse gains nothing
(measured −9%); dense has slack and gains (+13%). Rust is identical, instruction for
instruction. The base entry at 1T is at the L2 wall, not the store wall, and so is everyone.

### F1. Alternate the sweep direction per factor (base: rules question; wheel: do it)
Sweep factor k upward and factor k+1 downward (both the dense chunk loop and the sparse chunk
loop; each stream just runs from its last chunk to its first). The tail of one sweep is the
head of the next, so it is still in L1. LRU simulation, 31 sweeps of 977 lines through a
768-line L1: hit rate 0% monotone, **76% alternating**. Expect sparse to fall from about 61k
towards the store floor (about 45k TSC cycles) and dense to fall too: **+10% to +20% at 1T on
Zen 5**, more under SMT where L2 is shared. Rules: the base text says "clears all non-primes
individually, increasing the number with 2 × factor on each cycle". A downward sweep steps by
2 × factor but decreasing. Grey. **Build and measure it as a probe on `hc/boustrophedon`, then
Chris asks the maintainers with the number in hand.** For the wheel there is no rules question:
planes are 33 KB (fits L1 at 1T, not under SMT), so alternate per group pass and per sparse
prime; expect about 0 at 1T and +3% to +6% at 96 threads. Falsify: if sparse cycles at 1T
don't drop by at least 10% with the direction alternated, the L1 story is wrong.

### F2. Blocking (rogiervandam's merged base entry): the other rules question
`PrimeC/solution_5/src/sieve_base.c` (`shakeSieve`, PR #995) is tagged `algorithm=base,
faithful=yes` and sieves 32 KB blocks with every factor per block; GordonBGood says the
maintainers refused segmentation. One of those is the precedent. If blocking is allowed, the
sieve becomes L1-resident for every phase: **+30% or more at 1T, more under SMT.** Chris (2026-10-11): build F1 and F2 anyway, on
`hc/champion-grey`, and remove them if the maintainers say no (RUN-PLAN.md). Chris: ask upstream about F1 and F2 in one issue, F1 first (it
keeps the outer loop and the stepping; F2 changes the loop nesting).

### F3. Wheel sparse loop: it is dispatch-bound, so count micro-ops, not stores
Compiled (`avx512skx-x16`, `--addressing=64`): per mark `sar` + `shlx` + `or mem` (RMW, about
3 µops) + `add`, about 51 µops per 8 marks, 6.4 cycles at 8-wide dispatch = 0.8 cycles/mark;
measured about 0.74 core cycles/mark. Zig's 0.60 means about 4.8 µops/mark. The asm-wheel dump
should show where Zig saves: an `or` that isn't RMW-form, a cheaper word index, or fewer loop
µops. Note `shlx` already masks the count (no `and $63`). A scatter/gather form (8 marks per
instruction) is 40+ µops on Zen and not worth it. Expect the dump to name the µop; then one
change. This also explains why the wheel loses 6% to SMT: dispatch-bound code gains nothing
from a sibling.

### F4. `PRIMES_DENSE_MAX` sweep for the wheel: 384, 512, 640 (runtime env var; no build)
hc-035 and hc-045 changed the costs on both sides of the breakeven. Group pass cost per prime
is about 150 cycles plus the pattern build; sparse costs about 197k/p. Expect flat to +2%.

### F5. Base dense: `--addressing=64` (one flag) and the x16 fold
The compiled dense loop spends 2 of 8 instructions per vector on `leal`/`movslq` (32-bit index
sign-extension). hc-006 judged the flag on the sparse loop, not dense. Expect 0 to +2% at 1T.
Separately, the `avx512skx-x8` target emits two 256-bit ops per 8-word vector; a target that
folds the masks into 512-bit ops would halve dense store issue. `avx512skx-x16` failed to fold
(ledger note after hc-002), probably compile-time blow-up over 16 lanes, not a hard limit: an
agent task. Expect 0 to +8% at 1T on AVX-512 machines only; dense gains 13% from SMT so it has
slack. Rules: yes (same per-composite source ORs).

### F6. AVX-512 off at 96 threads on the 96-vCPU node (power, not instructions)
At 32 threads AVX-512 off cost 2%. On a near-whole socket the all-core clock is power-limited,
and 512-bit ops draw more: the AVX2-only build may run a higher all-core clock for every phase.
The Threadripper is bare metal and power-limited; the EPYC runner is AVX2 anyway. Expect −2% to
+4% at 96 threads; if positive, the submission could pick the AVX2 path at all threads and
AVX-512 at 1T (two dispatch sets; honest tags either way). Cheap: the build exists.

### F7. Next-prime scan, branchless (4% of the pass, about 168 mispredicts)
hc-009 lost 1.4%, which is odd for a `tzcnt` scan over 8 words. Worth one careful retry only
after F1–F6; ceiling +3%.

### What not to do (from this pass)
- Interleave two factors' sweeps (grey; same L2 traffic anyway).
- Software prefetch of all 8 lines per chunk: 8 extra AGU ops per chunk makes the loop
  AGU-bound (16 → 24 ops per 8 composites). If IDEAS 21 is built, prefetch at most 2 lines per
  chunk and only for p < 512, where chunk lines are shared by several ORs.
- Scatter/gather for the wheel's sparse marks.
- Striped layouts: Swift's is plain packed bits; its Threadripper number is machine-specific.

### For the PR and the write-up
"At one thread the leading base entries are all bound by L2 traffic that the rules fix: every
factor sweeps a sieve larger than L1. Our compiled sparse loop is Rust's, instruction for
instruction; the remaining 1–3% is the machine. The all-threads race is decided by what each
entry leaves for a sibling hardware thread." That is a claim a reviewer can check from
`results/hc/asm-sparse/README.md` and `results/hc/mt-phases-96/`.
