# Optimization Ideas for Base (ISPC) and Wheel Prime Sieve Entries

This document outlines 13 ranked, concrete optimization proposals for the ISPC odd-only base sieve entry and the mod-30 wheel sieve entry in the PlummersSoftwareLLC/Primes benchmark ("drag race").

Target runners:
- 96-core AMD Zen 5 Threadripper 7995WX / 9995WX (192 hardware threads, 32 KB L1I, 48 KB L1D, 1 MB L2/core, 12 CCDs).
- 128-vCPU AMD EPYC (AVX2, shared virtualized execution resources).

Target constraints:
- Base algorithm constraints (`algorithm=base, faithful=yes, bits=1`): Factors checked sequentially starting at 3; non-primes cleared individually stepping by $2 \times \text{factor}$; no hand-written multi-bit masks; no segmented sieves (pending maintainer clarification); dense threshold not raised past 128.
- Evaluation metric: Sieve count up to 1,000,000 in 5 seconds (single-threaded and all threads saturated).

---

## Ranked Optimization Ideas

### 1. Compact Periodic Kernels to Shrink Dense Code Footprint (from 422 KB to under 32 KB)

* **Entry:** Base (ISPC)
* **Target phase & architectural justification:** Dense phase (35% of total cycles, 422 KB code footprint).
  Zen 5 cores feature a 32 KB L1 Instruction Cache (L1I) and a 6.75K uop Op Cache. Under 192-thread SMT execution (two threads per physical core), both threads contend for the same 32 KB L1I. A 422 KB dense code segment violently thrashes the L1I and Op Cache thousands of times per second per core, causing frontend starvation and pipeline bubbles. Restructuring the ISPC dense phase to factor out repetitive unrolling and generate compact periodic kernels (leveraging factor periodicity mod 8 or mod 64) keeps the entire dense loop kernel resident in the 32 KB L1I.
* **Allowed for faithful base under CONTRIBUTING.md:** **Yes**. The base algorithm rules govern the order and stepping of composite identification ($2 \times \text{factor}$). Loop restructuring and unrolling depth decisions do not alter how non-primes are identified or cleared.
* **Expected gain:** 4–7% single-threaded; 15–25% at 192 threads under full SMT saturation.
* **How to falsify in one A/B test:** Measure `L1-icache-load-misses` and total passes using `perf stat` across 192 threads before and after capping unrolling depth. If L1I misses do not drop by at least 70% or throughput does not increase, falsify the idea.

---

### 2. Thread-Local Dynamic Arena Allocator for Sieve Buffers

* **Entry:** Both (Base & Wheel)
* **Target phase & architectural justification:** Buffer allocation and lifecycle management across passes.
  At ~100k cycles per pass, a single thread runs 40,000–50,000 passes per second. Across 192 threads, this generates 8+ million dynamic heap allocations and deallocations per second. Standard libc allocators (`malloc`/`free`) suffer arena contention, lock bouncing, and TLB churn across 12 CCDs. Providing a thread-local bump arena that allocates the exact requested size dynamically and resets without calling kernel memory APIs removes memory management bottlenecks under heavy thread counts.
* **Allowed for faithful base under CONTRIBUTING.md:** **Yes**. CONTRIBUTING.md requires that the sieve class encapsulates state, that each iteration re-creates an instance, and that the buffer is sized and allocated dynamically at runtime. As long as the allocation call occurs dynamically inside the instantiation path with the exact size, custom allocators are fully compliant (as verified in existing top C++ and Zig solutions).
* **Expected gain:** Negligible at 1 thread (<1%); 12–20% at 192 threads / 128 vCPUs.
* **How to falsify in one A/B test:** Benchmark 192 threads with default glibc allocator versus a thread-local bump-reset arena; measure `context-switches`, `page-faults`, and passes per second. If multi-threaded throughput does not improve by >8%, falsify.

---

### 3. Single-Base Scaled Offset Addressing in Wheel Strided Loops

* **Entry:** Wheel (mod-30)
* **Target phase & architectural justification:** Large-prime strided phase (targeting the 5–8% gap against the Zig port).
  On x86-64, only 15 general-purpose registers are available. Maintaining 8 separate 64-bit pointers alongside indices, loop bounds, and strides forces register allocators to spill addresses to the stack inside hot loops. Zig avoids spills by indexing off a single base register (`base + plane_index * plane_stride + offset`) with `noalias` guarantees. Switching to single-base addressing eliminates register spilling in the inner strided loop.
* **Allowed for faithful base under CONTRIBUTING.md:** **N/A** (applies to the Wheel entry, classified as `algorithm=wheel`).
* **Expected gain:** 5–8% on the wheel entry, matching or exceeding Zig performance.
* **How to falsify in one A/B test:** Disassemble the inner strided loop of both the current implementation and the single-base implementation; check for stack reads/writes (`mov [rsp+...], ...`). If stack spills are eliminated and the pass rate does not rise by >4%, falsify.

---

### 4. Dual-Factor Interleaved Stepping in the Sparse Phase

* **Entry:** Base (ISPC)
* **Target phase & architectural justification:** Sparse phase (61% of total cycles, store-bound profile).
  Zen 5 features two dedicated store pipes and a 72-entry store queue. Processing a single prime sequentially stresses a single address stream and causes store buffer stalls (store queue drain latency). Interleaving two independent primes ($p_a$ and $p_b$) in the sparse loop body alternates memory operations across two separate streams, maximizing dual AGU utilization and instruction-level parallelism (ILP).
* **Allowed for faithful base under CONTRIBUTING.md:** **Unsure**. Line 248 defines an outer loop that searches for the next prime and clears its multiples. Processing primes in pairs maintains individual composite clearing at $2 \times \text{factor}$, but interleaving two factors within the clearing step stretches the strict interpretation of "clearing this prime's multiples" sequentially. Requires clarification with maintainers.
* **Expected gain:** 6–10% on the sparse phase (~4–6% overall).
* **How to falsify in one A/B test:** Implement two-prime interleaving for factors between 128 and 500. Measure IPC and `resource_stalls.sb` via `perf stat`. If store buffer stalls do not drop and overall pass count does not increase by >3%, falsify.

---

### 5. 16-Composite Unrolling for the Sparse Loop

* **Entry:** Base (ISPC)
* **Target phase & architectural justification:** Sparse phase (61% of total cycles).
  At 8 composites per 12 instructions, loop branches, counter decrements, and condition evaluations account for ~17% of executed instructions. Expanding to 16 composites cuts branch and loop maintenance overhead in half and provides the Zen 5 out-of-order scheduler a wider window to co-issue memory writes across cycles.
* **Allowed for faithful base under CONTRIBUTING.md:** **Yes**. Unrolling does not combine marks into wider stores or alter the mathematical sequence of marks; each composite is still cleared individually with its own bit operation.
* **Expected gain:** 2–4% overall.
* **How to falsify in one A/B test:** A/B test the 8-way versus 16-way sparse loop on a single thread; measure `branch-instructions` and `cycles`. If instructions per pass do not decrease and elapsed time does not improve, falsify.

---

### 6. Hardware Thread Pinning and SMT-Aware Affinity Topology

* **Entry:** Both (Base & Wheel)
* **Target phase & architectural justification:** Multi-threaded scaling across 5 seconds.
  The 96-core Zen 5 Threadripper contains 12 CCDs, each with an independent L3 cache slice. If the OS scheduler migrates threads across CCD boundaries, warm L1/L2 data is invalidated, triggering costly interconnect traffic. Pinning guarantees cache locality and avoids SMT resource sharing when thread counts are less than or equal to physical cores.
* **Allowed for faithful base under CONTRIBUTING.md:** **Yes**. Thread dispatch, affinity, and runtime coordination are external to the sieve algorithm and permitted across all multi-threaded entries.
* **Expected gain:** 6–12% at 192 threads on Threadripper; 4–8% on 128-vCPU EPYC.
* **How to falsify in one A/B test:** Compare free OS scheduling against pinned affinity under a full 192-thread run. Check thread migration counts via `perf stat -e cpu-migrations`. If throughput does not rise by >5%, falsify.

---

### 7. Word-Granular Trailing-Zero Scan (`tzcnt`) for Next-Prime Search

* **Entry:** Base (ISPC)
* **Target phase & architectural justification:** Next-prime scan phase (4% of total cycles).
  Testing factors up to $\sqrt{1,000,000} = 1,000$ requires scanning only 500 bits in an odd-only array, which fits into just eight 64-bit words. A scalar loop incurs multiple unpredictable branches. Using `_tzcnt_u64` inspects up to 64 candidates per cycle without branch mispredictions.
* **Allowed for faithful base under CONTRIBUTING.md:** **Yes**. Line 254 states that "the algorithm sequentially checks all odd numbers, starting at 3." Scanning words sequentially via trailing zero count finds candidates in strict ascending order, identical to scalar checks (widely accepted in Rust, C++, and Zig base implementations).
* **Expected gain:** ~3% overall (reclaiming roughly three-quarters of the 4% scan time).
* **How to falsify in one A/B test:** Profile cycles specifically inside `find_next_prime`. If cycles spent in factor scanning do not drop by at least 60%, falsify.

---

### 8. Native 512-bit AVX-512 Vector Streaming for Wheel Pattern Fill

* **Entry:** Wheel (mod-30)
* **Target phase & architectural justification:** Small prime pattern streaming (Wheel entry).
  Zen 5 features two native 512-bit execution pipes with no frequency penalty. Storing 64 bytes per instruction doubles store throughput compared to AVX2 (32 bytes) and dramatically reduces uop pressure in the store buffer.
* **Allowed for faithful base under CONTRIBUTING.md:** **N/A** (Wheel entry).
* **Expected gain:** 4–6% for the wheel entry on Zen 5; neutral on AVX2 EPYC (where it falls back to 256-bit).
* **How to falsify in one A/B test:** Compile the wheel entry with AVX2 versus AVX-512 target flags on Zen 5 and measure passes in 5 seconds. If AVX-512 does not beat AVX2 by >3%, falsify.

---

### 9. 64-Byte Cache-Line Alignment and Tail Padding

* **Entry:** Both (Base & Wheel)
* **Target phase & architectural justification:** Memory pipeline efficiency across all clearing phases.
  Unaligned bit arrays risk split-line access where a single memory read-modify-write spans two distinct cache lines. Split stores take a 15–20 cycle latency hit and stall the store queue on Zen 5. Exact alignment guarantees zero split accesses.
* **Allowed for faithful base under CONTRIBUTING.md:** **Yes**. CONTRIBUTING.md mandates dynamic allocation sized to the sieve, and rounding up buffer allocation to the nearest cache line is standard practice for hardware alignment.
* **Expected gain:** 1–3% single-threaded; 3–5% multi-threaded where cache line conflict penalties are magnified.
* **How to falsify in one A/B test:** Force an intentional 1-byte misalignment on the buffer pointer and compare against 64-byte alignment; measure `mem_trans_retired.load_latency` or split store events with `perf`. If no difference is detected, falsify.

---

### 10. Inverted Logic with L1/L2 Hot Zeroing

* **Entry:** Base (ISPC)
* **Target phase & architectural justification:** Sieve reset/initialization phase.
  Inverted logic eliminates bitwise NOT operations during marking (changing `AND ~mask` to `OR mask`). Furthermore, clearing an L1/L2-resident 62.5 KB buffer to zero using AVX-512 takes under 350 cycles. Non-temporal stores (`movntdq`) should be avoided because the buffer must immediately be read during the sieve pass; keeping it in L1/L2 prevents cache misses.
* **Allowed for faithful base under CONTRIBUTING.md:** **Yes**. CONTRIBUTING.md line 260 explicitly states: "Inverted prime marking logic (marking primes as zero/false and non-primes as one/true) is permissible."
* **Expected gain:** 2–3% overall.
* **How to falsify in one A/B test:** Measure execution time of normal logic (`1 = prime`, requiring `memset` of `0xFF` and `AND` masking) versus inverted logic (`0 = prime`, zeroing and `OR` masking). If inverted logic does not yield higher pass counts, falsify.

---

### 11. Selective Software Prefetching for Sparse Factor Streams Under SMT

* **Entry:** Base (ISPC)
* **Target phase & architectural justification:** Sparse phase for large factors under high multi-threading load.
  When 192 threads run on 96 cores, the aggregate working set (62.5 KB $\times 2 = 125$ KB per core) exceeds the 48 KB L1D cache, causing continuous eviction to L2. While hardware prefetchers struggle with large, scattered strides across multiple threads, software prefetching brings the line into L1 before the read-modify-write occurs.
* **Allowed for faithful base under CONTRIBUTING.md:** **Yes**. Software prefetch instructions are hardware hints with no architectural state changes or algorithmic effects.
* **Expected gain:** Neutral or slight regression (-1%) at 1 thread; +3–6% under 192-thread contention.
* **How to falsify in one A/B test:** Run 192 threads with and without the prefetch instruction on large factors. Measure `L1-dcache-load-misses`. If misses do not decrease or passes do not increase, falsify.

---

### 12. Persistent Spin-Wait Worker Pool with Zero Cross-Thread Synchronization

* **Entry:** Both (Base & Wheel)
* **Target phase & architectural justification:** Multi-threading synchronization overhead.
  Contention on shared pass counters or barriers creates cache-line bouncing across the multi-CCD interconnect. Thread-local counters residing on independent cache lines eliminate all inter-core write invalidations during the 5-second measurement window.
* **Allowed for faithful base under CONTRIBUTING.md:** **Yes**. Multi-threading harness design is separate from the single-sieve algorithm definition.
* **Expected gain:** 3–6% at 192 threads / 128 vCPUs.
* **How to falsify in one A/B test:** Check pass count variability between threads and profile atomic lock contention via `perf c2c`. If cache invalidations or lock times do not drop, falsify.

---

### 13. Compile-Time Static Wheel Pattern Rolling with Aligned Vector Broadcasts

* **Entry:** Wheel (mod-30)
* **Target phase & architectural justification:** Template roll phase in the Wheel entry.
  Rolling the base pattern across 33.3 KB of memory using scalar or variable-length copies wastes cycles that could be spent on striding. An unrolled AVX2/AVX-512 register broadcast can populate the entire 33.3 KB structure in approximately 500 cycles.
* **Allowed for faithful base under CONTRIBUTING.md:** **N/A** (Wheel entry).
* **Expected gain:** 2–4% on the wheel entry.
* **How to falsify in one A/B test:** Profile cycle count of the wheel initialization function before and after switching to compile-time vector broadcast. If roll cycles do not decrease by >50%, falsify.

---

## Summary Ranking Matrix

| Rank | Idea | Target Entry | Target Phase | CONTRIBUTING.md Status | Expected Impact (192-Thread / SMT) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | Compact Periodic Kernels (Shrink 422 KB code) | Base (ISPC) | Dense Phase | **Yes** | **High (+15–25%)** |
| **2** | Thread-Local Dynamic Arena Allocator | Both | Lifecycle / Alloc | **Yes** | **High (+12–20%)** |
| **3** | Single-Base Scaled Offset Addressing | Wheel | Strided Phase | **N/A (Wheel)** | **Medium-High (+5–8%)** |
| **4** | Dual-Factor Interleaved Stepping | Base (ISPC) | Sparse Phase | **Unsure** (maintainer check) | **Medium (+4–6%)** |
| **5** | 16-Composite Unrolling | Base (ISPC) | Sparse Phase | **Yes** | **Medium (+2–4%)** |
| **6** | Hardware Thread Pinning & CCD Affinity | Both | Concurrency | **Yes** | **Medium-High (+6–12%)** |
| **7** | Word-Granular Trailing-Zero Scan (`tzcnt`) | Base (ISPC) | Scan Phase | **Yes** | **Low-Medium (+3%)** |
| **8** | Native 512-bit AVX-512 Pattern Streaming | Wheel | Small Prime Fill | **N/A (Wheel)** | **Medium (+4–6%)** |
| **9** | 64-Byte Cache-Line Alignment & Padding | Both | Store Pipeline | **Yes** | **Low-Medium (+3–5%)** |
| **10** | Inverted Logic with L1/L2 Hot Zeroing | Base (ISPC) | Pre-sieve Reset | **Yes** | **Low (+2–3%)** |
| **11** | Selective Software Prefetching for Large Strides | Base (ISPC) | Sparse Phase | **Yes** | **Medium (+3–6% under SMT)** |
| **12** | Persistent Spin-Wait Worker Pool | Both | Concurrency | **Yes** | **Medium (+3–6%)** |
| **13** | Compile-Time Static Wheel Vector Roll | Wheel | Template Roll | **N/A (Wheel)** | **Low-Medium (+2–4%)** |
