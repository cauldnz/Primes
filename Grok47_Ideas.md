# Ranked ideas (10 October)

The official score is all threads. On Zen 5 the base entry leads Rust by about 14% only when threads equal vCPUs, and by about 2.5% when half the vCPUs are idle. At 1 thread the phases match: about 100k cycles, 61% sparse, 35% dense, 4% scan. The compiled sparse loops are the same 12 instructions per 8 composites. Do not spend a run on that loop's instruction mix.

"Base-legal" below means `algorithm=base,faithful=yes,bits=1` as written in `CONTRIBUTING.md`: search odd numbers from 3, clear each non-prime individually stepping by `2 * factor`, fresh instance and a runtime buffer sized to the sieve, one bit per odd number. It does not mean the stricter single-bit-OR reading used inside this fork. Widening a store so one instruction clears several composites is excluded anyway, as is raising `DENSE_LIMIT` (hc-031, −7%) and segmentation.

Gains are a share of passes at threads = vCPUs unless noted. One A/B means same node, interleaved, discard round 1, at least five rounds, candidate against the current champion. If the all-threads median does not move, revert even if 1 thread rose.

## 1. Pin workers, then remeasure the 14%

**Change.** In the thread starter (not in `run_sieve`), pin worker `i` to allowed CPU `i` from `sched_getaffinity`. For the half and quarter lines, pin one thread per physical core using `thread_siblings_list`.

**Phase.** All of them. A 62.5 KB sieve that migrates across CCDs leaves its L2. Two SMT siblings on one core split the two store ports the sparse loop is waiting on. The 14% lead appears only at full occupancy, which is when the scheduler is out of idle cores.

**Base-legal.** Yes. Pinning is not sieve state. Each pass still allocates a new `Sieve`.

**Gain.** 0–4%, or the whole 14% if the lead is placement. About 0 at 1 thread.

**Falsify.** One A/B at 64 vCPUs, pinned against unpinned, same binary, at 64/64 and 32/64. Flat at both means pinning is not the cliff.

## 2. One thread reads the clock

**Change.** One watcher thread calls `clock_gettime` and sets a relaxed atomic. Workers in `worker` test that flag instead of calling `now()` every pass. davepl's C++ entry already uses a stop flag.

**Phase.** Outside the 100k. At 1 thread the call is lost in the noise. At 192 threads that is on the order of 10⁷ `clock_gettime` calls per second against one vdso seqlock.

**Base-legal.** Yes. The flag is not sieve state.

**Gain.** 0–3% at 128–192 threads. About 0 at 1 thread.

**Falsify.** One A/B at 64/64 only. If the ratio to Rust does not move, the clock is not why Rust falls off.

## 3. Count threads with `sched_getaffinity`, not `get_nprocs`

**Change.** `main` in both entries uses `get_nprocs()` (`primes_base.ispc` around the `clamp(get_nprocs(), …)` call). A runner started under `taskset` or a cpuset then oversubscribes, and oversubscription is exactly the case where the 14% disappears.

**Phase.** The all-threads line only.

**Base-legal.** Yes.

**Gain.** 0 on a normal VM. Large if the official runner restricts the cpuset and we currently spawn one thread per machine CPU.

**Falsify.** `taskset -c 0-7` and check that the printed thread count is 8, not the host's CPU count. This is a correctness check, not a speed test.

## 4. Shrink the 422 KB dense text without adding factors

**Change.** Keep `DENSE_LIMIT` at 128. Build the vector dense kernel as `avx2-i64x4` and `avx512skx-x4` (one 64-bit word per lane) instead of an 8- or 16-wide gang. A local compile of that shape dropped `clear_factor` from 422 KB to about 295 KB and the masks still folded. Also mark the composite cases (9, 15, 21, …) cold, or put them in a separate function, so the 31 prime kernels sit in one contiguous span. The `switch` must still list every odd factor.

**Phase.** Dense, 35% at 1 thread. Under SMT two threads share a 32 KB L1I and run different factors, so a 422 KB body is fetched over and over. Rust's 64 dense functions are 89 KB. hc-031 showed that adding factors makes this worse, which is why this idea only shrinks text.

**Base-legal.** Yes. `clear_dense_vec` still has one single-bit OR per composite in the source. The compiler folding them is the same transform as hc-002. Layout is not an algorithm change.

**Gain.** 0–4% at threads = vCPUs, less at 1 thread. The 295 KB figure was a compile measurement, not a benchmark.

**Falsify.** One A/B of the `i64x4` / `x4` targets at 16/16 or 64/64. Revert if all-threads is flat and 1 thread drops. Grep the asm for `vblendv` / `vpcmpeq` first; a correct but unfolded kernel is a loss.

## 5. AVX-512 off, measured only at full socket

**Change.** A build of the base entry with `ISPC_TARGETS=sse4-i32x4,avx2-i32x8`, no `avx512skx`. Do not change the source.

**Phase.** Dense. A full Zen 5 socket of 512-bit ops can cut package boost. hc-013 was +1.0% at 1 thread. That can flip when every core is busy. The 128-vCPU EPYC runner is AVX2-only, so this also says whether the Zen 5 all-threads lead depends on a target that runner does not have.

**Base-legal.** Yes.

**Gain.** −1% to +4% at 64/64. 1 thread may give back the 1%.

**Falsify.** One A/B at 64/64, six rounds. If the no-AVX-512 build loses there, keep AVX-512.

## 6. glibc arenas, not a recycled buffer

**Change.** Before `pthread_create`, `mallopt(M_ARENA_MAX, nthreads)` (or the opposite, one arena). Still `aligned_alloc` and `free` inside each pass. Do not keep a free list across passes.

**Phase.** Set-up. TSC puts it at 0.1k cycles at 1 thread, against Rust's 0.9k. A malloc lock does not show up until every vCPU is in `aligned_alloc` together. Page-fault counts already failed to explain Rust's drop, so this is the next allocator hypothesis, not a repeat of that check.

**Base-legal.** Yes for `mallopt`. A free list that hands the same pages back is unsure: `CONTRIBUTING.md` requires each iteration to recreate the instance from scratch and to allocate the buffer at runtime. Recycling is state between passes. Use it only as a probe.

**Gain.** 0–5% at 128–192 threads if the cliff is the allocator. About 0 at 1 thread.

**Falsify.** One A/B, `MALLOC_ARENA_MAX=8` against `192`, same binary, 64/64. Flat means stop. If a recycle probe gains and `mallopt` does not, the gain is unfaithful and stays a probe.

## 7. Immediate byte offsets for the heavy sparse primes

**Change.** In `clear_sparse_e`, the eight offsets are runtime registers (`orb $imm, (%rsi,%rIdx,1)`). For each odd factor from 131 to 191, emit a copy whose offsets are `imm8` (`orb $imm, imm8(%rsi)`), with the current function as the fallback. Still eight single-byte ORs per chunk. Do not OR several bits into one mask.

**Phase.** Sparse, 61%. At 1 thread this loop is store-bound and identical to Rust, so a 1-thread win is unlikely. At full occupancy the two store ports and the AGUs are shared with a sibling. An `imm8` offset is a shorter address form and frees eight registers. llvm-mca on a Zen 4 model called the loop AGU-bound; Zen 5 has four AGUs, so this may already be free.

**Base-legal.** Yes. One OR per composite, step still `2 * factor`, and every odd value in the band has a case or falls through. No prime table.

**Gain.** 0–3% of the pass at threads = vCPUs. About 0 at 1 thread.

**Falsify.** One instrumented A/B at 64/64. If the sparse-phase TSC does not drop, revert. Do not judge it on the sandbox Xeon.

## 8. Wheel: one allocation, break 4 KB aliasing

**Change.** `sieve_create` does two `aligned_alloc`s, planes at `pw` words and `Group.buf[G][MAXPAT+…]`. If `pw * 8` bytes is a multiple of 4 KB, the eight sparse streams hit one L1 set. Put planes and pattern rows in one runtime block, and stagger rows by 64 bytes plus an odd number of cache lines. The Zig wheel's arena does not use this split. hc-043 already copied Zig's sparse loop and lost 4% at 1 thread and 19% at 16 threads, so the remaining gap is not that loop shape.

**Phase.** Wheel sparse. On Zen 5, after the unsigned `start_bit` fix, Zig is still ahead by 4.6%, and the phase gap is sparse: 29.9k cycles against 24.0k. Groups are tied on Zen 5 (32.7k against 31.9k) and not tied on Zen 3 (59.6k against 50.4k), which is the AVX2 EPYC runner.

**Base-legal.** No. This is wheel storage. Applying it to the base entry does not make sense. For the wheel entry it stays faithful if the block is sized from the sieve, allocated at runtime, and held in `struct Sieve`.

**Gain.** 0–5% of the wheel pass. More at all-threads if two siblings alias the same sets. Aliasing is a candidate for the remaining Zig gap, not a measured cause.

**Falsify.** One phase-timed A/B, layout only. If Zen 5 sparse stays at 29.9k, aliasing is not the gap. Revert.

## 9. Wheel sparse: eight pointers and an immediate rotate, not Zig's unroll

**Change.** `sparse_prime` recomputes `base[i[pl] >> 6] |= 1 << (i[pl] & 63)` per mark. Split once into a pointer and a mask per plane. Step the pointer by `p >> 6`. Rotate the mask by `p & 63`, specialized into 32 copies so the rotate is an immediate. Do not add `#pragma unroll 4` and do not share one counter across streams. That was hc-043, and it lost.

**Phase.** The same 29.9k against Zig's 24.0k. About 57k marks, so ISPC is near 0.5 TSC cycles per mark and Zig is near 0.4. A rotate does not remove stores. It removes the variable shift, which is the uop a sibling steals when both threads are in this loop.

**Base-legal.** No. Wheel only. One bit per mark, so `bits=1` is unchanged.

**Gain.** 0–4% of the wheel at all-threads. It can regress the way hc-043 did if it spills.

**Falsify.** If the all-threads median drops on the first five rounds, revert. Do not keep a 1-thread win that loses at 16 threads.

## 10. Wheel: OR 13's pattern into the tile copy

**Change.** The tile copy is `w[base + k] = w[k]`. Make it `w[base + k] = w[k] | pat13[r]`, then drop the separate sweep for 13. Clear bit 0 of plane 13 afterwards, as the tile already clears 7 and 11.

**Phase.** Tile plus 13: 1.3k + 1.5k on Zen 5, about 4% of a 68k pass. The extra 33 KB write is L2 bandwidth an SMT sibling also wants. Small at 1 thread, which is why it is ranked for the full machine.

**Base-legal.** No. A pattern word sets many composites in one store. Legal for a wheel entry. Not legal as a base-entry change.

**Gain.** 1–3% at all-threads, under 2% at 1 thread.

**Falsify.** Phase timers. If tile+13 does not fall by about 1k cycles, revert.

## 11. `--cpu=znver5` only if all-threads goes up

**Change.** One ISPC flag, `--cpu=znver5` (or `znver4` if 1.22 rejects `znver5`), on both entries. No source change. hc-041 (`--cpu=znver3`) was +3.7% at 1 thread and −3.1% at 16 threads on Zen 3. Same hazard.

**Phase.** Whichever loop the scheduler was scheduling for a generic CPU. Most likely the wheel sparse shift loop and the base `orb` loop.

**Base-legal.** Yes. Codegen only.

**Gain.** −3% to +3%. Sign unknown. The 16-thread loss on hc-041 is why this is not higher.

**Falsify.** One A/B at threads = vCPUs. Revert if that median drops, even if 1 thread rose.

## 12. Half and quarter lines: one thread per core

**Change.** When spawning `n/2` or `n/4` threads, place them on distinct physical cores, not on SMT siblings. Read `thread_siblings_list`. The all-threads line stays one thread per vCPU.

**Phase.** The published half and quarter lines. Two store-bound sieves on one core each get one store port.

**Base-legal.** Yes.

**Gain.** 0–8% on the half line of a 192-thread box. 0 on the all-threads line, which is why this is below the occupancy ideas.

**Falsify.** One A/B at 96 threads on a 192-thread machine, packed against spread. Flat means the kernel is already placing them that way.

## 13. Huge pages only if the DTLB is actually missing

**Change.** `madvise(MADV_HUGEPAGE)` on the exact sieve allocation. Do not allocate a 2 MB buffer for a 64 KB sieve.

**Phase.** Set-up and the first touch of each pass, at 192 threads. A 64 KB sieve is 16 pages of 4 KB.

**Base-legal.** Yes if the allocation size still matches the sieve. A 2 MB allocation is not: the buffer size must correspond to the sieve size.

**Gain.** 0–2% at 192 threads, and only if DTLB misses show up. Expect about 0, because 16 pages fit in the DTLB.

**Falsify.** One counter check at 64/64. If the DTLB miss rate is already about 0, do not build it.

## 14. What not to run, so the next A/B is not a repeat

These lost, or they are the excluded items.

- Raising the dense cutoff. hc-031 to 191, −7.2% at 1 thread. hc-036 down to 96, −2.5% on Zen 3 and flat on Zen 5.
- Any sparser instruction mix that still does one byte RMW per composite. The Zen 5 asm is already Rust's loop.
- One word mask with several composites set. Excluded for base. davepl's `stepMasks` is that, and it is not a base-entry change under the reading used here.
- Segmentation, including "every prime, one L1 block at a time".
- Wheel sparse in Zig's counted, unroll-4 form. hc-043, −19% at 16 threads on Zen 5.
- Two gangs per group step. hc-042, flat.
- A recycled sieve buffer as a submission. Fine as a probe for idea 6. Not faithful if it is shipped.

## Order

1. Ideas 1 and 3 on the next 64-vCPU run. They decide whether the 14% is the sieve or the scheduler.
2. Idea 2 in the same binary if idea 1 is cheap to combine. If a clean A/B is wanted, run it alone.
3. Idea 4, then 5, on the base entry. Both are full-occupancy bets on the 422 KB body.
4. Idea 8 on the wheel. It is the remaining Zig gap, and hc-043 already removed the loop-shape explanation.
5. Ideas 6, 7, 9, 10, 11 only if the one above them is flat.
