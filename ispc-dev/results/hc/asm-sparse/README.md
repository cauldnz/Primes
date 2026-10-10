# Sparse-marking hot loops as compiled: ISPC base vs Rust vs Swift (Zen 5)

Source: `Standard_D16as_v7.txt` (13 MB, not committed), the output of the `hc/diag-asm-sparse`
image on one Azure D16as_v7 (AMD EPYC 9V45, Zen 5, AVX-512). It holds `objdump -d -M att`
output for three binaries, each built the way its own Dockerfile builds it (see
`git show origin/hc/diag-asm-sparse:PrimeISPC/solution_2/Dockerfile` and `dump.sh`):

| entry | source | build |
|---|---|---|
| ispc | `PrimeISPC/solution_2/primes_base.ispc` on `origin/hc/champion` (`clear_sparse_e`) | ispc -O3, targets sse4/avx2/avx512skx-x8; Zen 5 dispatches to **avx512skx** |
| rust | mike-barber `PrimeRust/solution_1`, bit-extreme-hybrid (`ResetterSparseU8::reset_sparse`) | rust 1.57, `cargo build --release` |
| swift | `PrimeSwift_1bitStriped_u8` (`markSparseMultiples`) | swift 6.3.3, `-O -wmo -target-cpu haswell` |

All three use the same source-level scheme for large factors: the bit array is viewed as bytes,
split into chunks of p bytes, and each chunk gets 8 single-bit ORs at fixed byte offsets with
constant masks (the masks depend only on p mod 16 or p mod 8, so each entry dispatches to a few
copies of the loop). Thresholds differ: sparse is p >= 129 for ispc (`DENSE_LIMIT 128`),
p > 129 for rust, and p >= 113 for swift. For n = 1,000,000 that is 133,075 composites cleared
in the sparse phase for ispc and rust, and 141,318 for swift.

## Where the loops are

Each loop was found by its back-edge (a conditional jump to a lower address in the same symbol)
whose body holds 8 or more `or` instructions with a memory destination (`loops/loops.py`).

- **ispc**: `clear_sparse` is inlined into `clear_factor___..._avx512skx`. Eight copies of the
  loop (one per p mod 16), at 0x6d940, 0x6da30, ... 0x6dfd0, all 12 instructions. Quoted:
  the first (E = 1). The avx2 `clear_sparse` copy has the same 12-instruction shape.
- **rust**: `reset_sparse` is inlined into the `run_implementation_st` instance that calls
  `extreme_reset_NNN` (ExtremeHybrid, at dump line 26574). Eight copies (one per equivalent
  skip 3..17), at 0x39d50, 0x39e70, ... 0x3a540, all 12 instructions. Quoted: 0x39d50.
  (The other `run_implementation_st` with 8 identical loops is the UnrolledHybrid variant; the
  `__rust_begin_short_backtrace` ones are the multi-threaded copies.)
- **swift**: `markSparseMultiples` is inlined into `PrimeSieve.runSieve()`
  (`$s15PrimeSieveSwift0aB0C03runB0yyF`). Four copies (p mod 8 = 1, 3, 5, 7), at 0x8be90,
  0x8c0d0, 0x8c310, 0x8c550, all 25 instructions. Quoted: 0x8be90.

`loops/*_raw.s` are the loops as dumped, `loops/*_context.s` add the set-up and tail code,
`loops/*_mca.s` are the llvm-mca inputs and `loops/*_mca.txt` the full llvm-mca output.

## Side by side

Per bit cleared (= per composite: every composite is its own byte OR in all three).

| entry | loop | insns/bit | loads/bit | stores/bit | RMW form | stride handling | unroll | mca cyc/iter | mca cyc/bit |
|---|---|---|---|---|---|---|---|---|---|
| ispc (ours) | 0x6d940, 12 insns, 8 bits | 1.50 | 1.00 | 1.00 | `orb $imm,(%rsi,%rIdx,1)` x8 | chunk pointer `rsi`; next pointer `rcx += p` (`r13`), `cmp end; jle`; 8 byte offsets in registers | 1 chunk = 8 composites | 5.34 | **0.67** |
| rust | 0x39d50, 12 insns, 8 bits | 1.50 | 1.00 | 1.00 | `orb $imm,(%rax,%rIdx,1)` x8 | chunk pointer `rax += p` (`r8`), remaining length `rbx -= p`, `cmp p; jae` (`chunks_exact`); 8 offsets in registers | 1 chunk = 8 composites | 5.34 | **0.67** |
| swift | 0x8be90, 25 insns, 16 bits | 1.56 | 1.44 (16 RMW + 6 spill reloads + 1 `cmp mem`) | 1.00 | `orb $imm,(%rBase,%rax,1)` x16 | byte index `rax += 2p` (`rdx`); 16 precomputed `bytes + offset` base pointers, 6 of them spilled and reloaded each iteration; bound `cmp -0xa8(%rbp)` | 2 chunks = 16 composites | 13.01 | **0.81** |

No entry has a bounds check inside the loop body. Tails: ispc and rust both run the 8 ORs of
the last partial chunk once after the loop, each guarded by a compare (`jge`/`jae` out).
Swift runs one more full group of 8 unguarded (it stops 2 groups before the end) and then a
guarded tail in separate code. Loop overhead is 4 instructions in each (ispc's
`mov %rcx,%rsi` is a register move that Zen eliminates at rename; `cmp`+`jcc` fuse).

**llvm-mca is a screen, not a verdict.** llvm-mca 18 has no Zen 5 model (`znver5` is rejected),
so `-mcpu=znver4` was used. That model issues each `orb` RMW as one load and one store using
two of three AGU slots, so 8 RMWs need 16/3 = 5.33 cycles: the reported bottleneck is
AGU/LSU pressure (99% of cycles) in all three, with the store pipes at 4 of 5.3 cycles busy
(2 stores per cycle). Zen 5 has four AGUs and still two store pipes, so on the real part the
ceiling is more likely the two stores per cycle (0.5 cycles/bit) than the AGU limit; the model
also ignores caches (the 62.5 KB bit array does not fit Zen 5's 48 KB L1D, and sparse strides
touch a new line every few ORs). Use the ratios between the loops, not the absolute numbers.

Measured cross-check (1 thread, same node): ours 24.1 us for 133,075 sparse composites =
181 ps/composite; Swift 29.8 us for 141,318 = 211 ps/composite, 1.17x ours per composite.
The mca ratio is 0.81 / 0.67 = 1.22x, roughly in agreement. At the 2 RMW/cycle store ceiling,
181 ps/composite corresponds to a clock of about 2.8 GHz; the clock was not recorded, so
whether we are at the store ceiling is inferred, not measured. There is no per-phase Rust
figure, but its sparse loop is instruction-for-instruction the same shape as ours.

## The loops (AT&T, as dumped)

ispc, `clear_factor___un_3C_s_5B_unSieve_5D__3E_uni_avx512skx` (inlined `clear_sparse_e`, E = 1):

```
   6d940:	orb    $0x1,(%rsi,%r14,1)
   6d945:	orb    $0x2,(%rsi,%r12,1)
   6d94a:	orb    $0x4,(%rsi,%r15,1)
   6d94f:	orb    $0x8,(%rsi,%rdx,1)
   6d953:	orb    $0x10,(%rsi,%rbx,1)
   6d957:	orb    $0x20,(%rsi,%rbp,1)
   6d95b:	orb    $0x40,(%rsi,%r8,1)
   6d960:	orb    $0x80,(%rsi,%r10,1)
   6d965:	mov    %rcx,%rsi
   6d968:	add    %r13,%rcx
   6d96b:	cmp    %rax,%rcx
   6d96e:	jle    6d940 <clear_factor___un_3C_s_5B_unSieve_5D__3E_uni_avx512skx+0x4a0>
```

rust, `prime_sieve_rust::run_implementation_st` (ExtremeHybrid instance, inlined
`ResetterSparseU8::reset_sparse`):

```
   39d50:	orb    $0x10,(%rax,%rsi,1)
   39d54:	orb    $0x20,(%rax,%r14,1)
   39d59:	orb    $0x40,(%rax,%rcx,1)
   39d5d:	orb    $0x80,(%rax,%r15,1)
   39d62:	orb    $0x1,(%rax,%rbp,1)
   39d66:	orb    $0x2,(%rax,%r11,1)
   39d6b:	orb    $0x4,(%rax,%r13,1)
   39d70:	orb    $0x8,(%rax,%r10,1)
   39d75:	add    %r8,%rax
   39d78:	sub    %r8,%rbx
   39d7b:	cmp    %r8,%rbx
   39d7e:	jae    39d50 <prime_sieve_rust::run_implementation_st+0x8e0>
```

swift, `$s15PrimeSieveSwift0aB0C03runB0yyF` (inlined `markSparseMultiples`, p mod 8 = 1):

```
   8be90:	orb    $0x80,(%rbx,%rax,1)
   8be94:	orb    $0x1,(%r8,%rax,1)
   8be99:	orb    $0x2,(%rdi,%rax,1)
   8be9d:	orb    $0x4,(%r15,%rax,1)
   8bea2:	orb    $0x8,(%rsi,%rax,1)
   8bea6:	orb    $0x10,(%r12,%rax,1)
   8beab:	orb    $0x20,(%r9,%rax,1)
   8beb0:	orb    $0x40,0x0(%r13,%rax,1)
   8beb6:	mov    -0xd0(%rbp),%r11
   8bebd:	orb    $0x80,(%r11,%rax,1)
   8bec2:	mov    -0xc8(%rbp),%r11
   8bec9:	orb    $0x1,(%r11,%rax,1)
   8bece:	mov    -0xc0(%rbp),%r11
   8bed5:	orb    $0x2,(%r11,%rax,1)
   8beda:	mov    -0xb8(%rbp),%r11
   8bee1:	orb    $0x4,(%r11,%rax,1)
   8bee6:	mov    -0xb0(%rbp),%r11
   8beed:	orb    $0x8,(%r11,%rax,1)
   8bef2:	mov    -0xa0(%rbp),%r11
   8bef9:	orb    $0x10,(%r11,%rax,1)
   8befe:	orb    $0x20,(%rcx,%rax,1)
   8bf02:	orb    $0x40,(%r10,%rax,1)
   8bf07:	add    %rdx,%rax
   8bf0a:	cmp    -0xa8(%rbp),%rax
   8bf11:	jl     8be90 <$s15PrimeSieveSwift0aB0C03runB0yyF+0x2d0>
```

## What this suggests

- **No entry does fewer stores per composite than ours.** All three do exactly one byte
  read-modify-write (one load, one store) per composite. For p >= 113 consecutive odd
  multiples are p bits apart, so no two share a byte or a 64-bit word: under the base rule
  (each composite cleared individually), one RMW per composite is the floor for scalar code.
- **Ours and Rust compile to the same loop**: 8 `orb $imm` with register-held offsets, 4
  overhead instructions, no spills. Swift's 2x unroll saves loop overhead but runs out of
  registers: 6 reloads plus a memory-operand compare per 16 composites, 44% more loads per
  composite. mca puts it 22% slower per composite and the measured gap is 17%. Swift's sparse
  phase is slower than ours both per composite and in total (it also covers 113..127).
- **Unrolling ours further is not supported.** A hypothetical 2x-unrolled version of our loop
  with no spills (`loops/ispc_unroll2_hypo.s`) screens at 11.34 cycles per 16 composites,
  0.71/bit, no better than 0.67: the loop is limited by memory operations, not instruction
  count or front end.
- **No change to the sparse inner loop is supported by this evidence.** Its instruction mix is
  already the minimum (1 RMW per composite, 0.5 overhead instructions per composite, no
  spills, no bounds checks), and the measured rate is consistent with Zen 5's two stores per
  cycle at an unrecorded clock of about 2.8 GHz. Things that would cut stores, such as
  combining several composites into one word write or cache-blocking the sparse primes over
  segments, either are impossible for p >= 129 (no two multiples share a word) or change the
  base outer loop (find a prime, clear all its multiples, repeat), which the base rules in
  `CONTRIBUTING.md` fix. AVX-512 scatter keeps each composite separate in principle, but it
  needs a gather-OR-scatter, which is slow on Zen 4 and Zen 5, and nothing here suggests it
  would win; treat it as an untested idea, not a recommendation.
- **Uncertainties**: no Zen 5 mca model; mca ignores L1/L2 misses, which may matter because
  the array is larger than L1D; the clock during the profile is unknown; Rust's sparse time
  was not measured separately. A perf-counter run (stores retired per cycle, L1D misses in
  the sparse phase) would settle whether the loop sits at the store limit or waits on L2.
  The remaining sparse-phase gains, if any, are more likely in the memory system than in the
  instruction stream.
