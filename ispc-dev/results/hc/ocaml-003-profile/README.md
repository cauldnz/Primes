# ocaml-003: where the plain OCaml base spends its cycles

Subject: `PrimeOCaml/solution_4/primes.ml` at 0b8d98c (branch `hc/ocaml-plain-base`), built with
OCaml 5.2 + flambda, `-O3 -unsafe -inline 200`.

Machine: a shared 4-vCPU cloud container, Intel Xeon at 2.8GHz (TSC 2.8GHz), not Zen 5. Here the
OCaml base does 16,100 passes in 5 s at one thread and the Rust port
(`hc/port-rust-base-champion`, `target-cpu=native`) does 52,400: a gap of 3.3 times, against 4.4
times on Azure Zen 5. Run-to-run noise on this box is about 5%, and one round in three was
10-30% slower across the board, so small differences below are not significant.

`perf` is installed but has no build for this kernel, so all numbers come from rdtsc timers in a
diagnostic build (`primes_diag.ml` plus `rdtsc_stub.c`, this folder; not for submission).

## Phases, one thread

10,000 passes after 200 warm-up passes; the cost of each rdtsc pair (30-37 cycles) is taken out.
Typical of three runs:

| Phase | Cycles/pass | us/pass | Share |
|---|---:|---:|---:|
| create (Bytes.create 62.5KB, includes any GC work it triggers) | 14,400 | 5.2 | 1.7% |
| dense: build_pattern (30 factors) | 43,900 | 15.7 | 5.1% |
| dense: pattern OR loop | 464,800 | 166.0 | 54.0% |
| sparse, factors >= 128 (137 factors) | 306,400 | 109.4 | 35.6% |
| next-prime scan | 5,200 | 1.9 | 0.6% |
| total | 860,000 | 307 | 100% |
| count_primes (first pass only, not in the total) | 3.9-4.3 million | 1,400-1,550 | |

Work per pass: 234,400 dense words (30 factors times about 7,800 words) and 133,500 sparse marks.
That is 2.0 cycles per dense word and 2.3 cycles per sparse mark.

GC per pass: 6 minor words, 8,332 major words (the sieve; the pattern buffer is 512 words, also
major), 0.29 minor and 0.29 major collections. Raising `space_overhead` to 200 or 1,000 cut the
collections to 0.17 and 0.006 a pass but did not move the total beyond noise. Allocation and GC
cost at most about 2%.

count_primes costs about 8 cycles per bit (a byte load, shift and test per bit). It runs once per
5 s, so it doesn't matter for the score.

## The compiled loops

From `ocamlopt -S` with the same flags.

Dense OR loop (`clear_dense`, not the init path): 44 instructions per four words, 11 per word.
Per word: two loads (sieve word, pattern word), one OR, one store, and two `sar` to untag the
byte index of each array, plus two to three `mov`/`add` to rebuild each address. The compiler
does not fold the constant offsets (+8, +16, +24) into the addressing mode; it adds them to the
tagged index and shifts again. One safepoint poll per four words (`cmp (%r14),%r15; ja`). No
spills. The init path (factor 3) is 36 instructions per four words.

Sparse loop (`clear_sparse`): 85 instructions per eight marks, 10.6 per mark. 16 offsets and
masks, the buffer, the index, the `for` counter and its limit are 20 live values, so the
register allocator spills 10 of them: each mark reloads its offset and mask from the stack. Per
mark: two stack loads, `lea`+`sar` for the address, `movzb`, `lea` to tag the byte, `or`, `sar`
to untag it, `movb`. The `for` counter is also loaded, incremented and stored to the stack every
chunk. One poll per chunk.

Scan (`run`): about 15 instructions per bit tested, including a reload of the sieve record and
its buffer from the stack each step. It is 0.6% of the pass.

The other two entries, per unit of work:

| Loop | OCaml | ISPC base (`primes_base.ispc`) | Rust port |
|---|---|---|---|
| dense, per 64-bit word | 11 instr: 2 loads, 1 store, 2 tag shifts, poll every 4 words | factor is a compile-time constant; vector OR with constant masks, about 1 instr per word (AVX2: load, or, store per 4 words) | factor is a const generic; masks from a table, LLVM vectorises: about 1 instr per word |
| sparse, per composite | 10.6 instr: 3 loads (2 from stack), 1 store, 2 tag shifts | 1 instr (`or byte [q+reg], imm8`), masks constant via `p mod 16` switch, pointer walk | same as ISPC: 1 memory-OR per composite |
| scan, per bit | about 15 instr | about 5 | about 5 |

So OCaml runs about ten times as many instructions per unit in both hot loops. It gets back part
of that by running them fast (around five per cycle in the dense loop), which is why the gap is
3-4 times and not ten.

## Quick trials

Same diagnostic build, three interleaved rounds of 4,000 passes, total cycles per pass (first two
rounds; the third round was slow for every variant):

| Variant | Round 1 | Round 2 | Dense cyc/word | Sparse cyc/mark |
|---|---:|---:|---:|---:|
| as submitted | 881,000 | 835,000 | 1.92-2.03 | 2.24-2.33 |
| dense: two runs at once, eight words a step (DENSE8) | 770,000 | 784,000 | 1.68-1.70 | 2.20-2.22 |
| sparse: two loops of four marks (no spills) | 888,000 | 943,000 | | 2.53-2.69 |
| sparse: as above, unaligned 64-bit ORs | 1,022,000 | 895,000 | | 2.59-2.85 |
| dense limit 64, original sparse (one run, 5,000 passes) | 780,000 | | | |
| dense limit 64, 64-bit sparse | 871,000 | 874,000 | | |

DENSE8 wins in every round: about 11% on the pass and 17% on the dense loop. Removing the sparse
spills by splitting the loop does not help; the sparse loop seems bound by its byte
read-modify-writes into a 62.5KB buffer that is bigger than L1, more than by instruction count.

## Ranked changes

All keep one OR per composite, all state per pass and no segmentation.

1. **Dense OR over two runs per step (eight words, one pattern load for two words).** Targets the
   dense loop, 54% of the pass. Measured here: dense loop 17% faster, pass 9-13% faster. Predict
   8-13% on Zen 5. Going to three or four runs a step may add a few per cent more.
2. **Dense loop on a Bigarray of int64 indexed by word.** Targets the dense loop. With a word
   index the compiler addresses `base + 4*tagged - 4` directly, so the two `sar` per word go and
   the constant offsets fold into the addressing mode: a test compile gives 7 instructions per
   word against 11 (it reloads the Bigarray data pointer each access, which is an L1 hit). Predict
   10-20% on the pass, on top of item 1. Risk: a Bigarray is a malloc'd custom block, which
   speeds up the major GC; measure create plus GC after the change. Byte access for the sparse
   phase would then need a second view (`Bigarray.reshape` or an int8 array over the same memory).
3. **Dense limit about 64-96 instead of 128.** Targets the split between dense and sparse. A
   dense factor costs about 17,000 cycles (7,800 words at 2 cycles, plus 1,500 for the pattern);
   a sparse one about 1.15 million / p cycles, so the break-even sits near p = 68. Measured: about
   10% at limit 64 in one run, noisy. Predict 0-8%; the best limit moves up again once items 1
   and 2 make the dense loop cheaper, so tune it last.
4. **Fewer instructions in the sparse loop.** Targets 36% of the pass, but the split-loop trial
   shows instruction count is not the limit there. Options still untried: a `while` over the byte
   index instead of the `for` counter (removes the counter spill), and processing two factors
   per chunk walk. Predict 0-5%.
5. **Allocation, GC and polls.** create plus GC is 1.7%; `space_overhead` changes gave nothing
   measurable at one thread. The poll is two instructions per four dense words (per eight with
   item 1) and 5.2 does not let us drop it in a plain build. Predict 0-3% combined. Leave alone.

The ten-to-one instruction gap against ISPC and Rust comes from SIMD and compile-time masks,
which plain OCaml cannot express. Items 1-3 together might reach 20-30%, closing the 4.4 times
gap on Zen 5 to about 3.4 times.

Not in scope but seen in passing: the four-domain run here makes 20,800 passes against 16,100 for
one domain (1.3 times), where Rust makes 179,600 against 52,400 (3.4 times).
