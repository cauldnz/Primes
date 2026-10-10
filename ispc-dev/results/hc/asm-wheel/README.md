# asm-wheel: ISPC wheel vs Zig wheel, compiled code side by side

Question (RUN-PLAN priority 3): why is the Zig port of the wheel (`PrimeZig/solution_4` on
`hc/zig-submission`, the `cauldnz-zig-wheel` entry) 4.6% (Zen 5) to 7.6% (Zen 3) faster than
the ISPC wheel it was ported from (`PrimeISPC/solution_1` on `hc/idea1-affinity`)?

Branch `hc/diag-asm-wheel` (DIAGNOSTIC, never merge) replaces the `PrimeISPC/solution_2` slot
with a multi-stage image that builds both on the node, exactly as their own Dockerfiles do:

| stage | base | build |
|---|---|---|
| ispc | ubuntu:24.04, apt `ispc` | `ispc/build.sh` = `solution_1/build.sh` verbatim: `-O3 --addressing=64 --pic --woff --target=sse4-i32x8,avx2-i32x16,avx512skx-x16` |
| zig | alpine:3.21, `zig=0.13.0-r1` | `zig/build.sh` = `solution_4/build.sh` verbatim: `-O ReleaseFast -fstrip -mcpu=native`; plus a twin `primes-sym` with the same flags minus `-fstrip` for the symbol table |

The run prints `asm;meta;...` (CPU model and flags, expected ISPC dispatch ISA, ISPC and Zig
versions, Zig's view of the native CPU name and features, `.text` sizes, and
`nm -S --size-sort --defined-only` of both binaries), then `asm;ispc;...` and `asm;zig;...`
(`objdump -d --no-show-raw-insn -M att`, capped at 40k lines per entry), then `asm;done`.
For every Zig function dumped from `primes-sym` it prints whether the same instruction
sequence (addresses and branch targets blanked) occurs in the stripped submission binary:
`## in stripped submission binary: identical|DIFFERENT`. `PRIMES_TEST=1` execs the ISPC wheel's
own self-test (10 .. 10^8), exit code passed through.

Symbols dumped (all others are inlined into these; checked with `nm` on local builds):

| | ISPC (avx512skx, then avx2; sse4 skipped) | Zig |
|---|---|---|
| fused group loop | `apply_group_*` | `WheelSieve.densePrimes` (holds `applyGroup` N=1..8, each specialised) |
| pattern set-up | `dense_primes_*` (`build_group`/`build_pattern`, `start_bit`, the n=1 `apply_range`) | `WheelSieve.densePrimes` (`buildPattern`, `startBit`) |
| sparse loop | avx512skx: inlined in `run_sieve_avx512skx`; avx2: `sparse_prime_avx2` | `WheelSieve.run` (`sparsePrime` inlined) |
| tile set-up / copy | `run_sieve_*` (tile `apply_group` call, foreach copy) | `WheelSieve.run` (tile `applyGroup(2)`), `memcpy`, `memset` (Zig compiler_rt) |
| start_bit | inlined everywhere | inlined everywhere |

## Zen 5 (Azure) results

_To be filled from the node run (`asm;` lines). Check first: `asm;meta;zig-native-cpu`
(Zig 0.13 is LLVM 18, which has no `znver5`; the vector width Zig picks follows from the
native features), `asm;meta;cpu;ispc dispatch expected`, and the `identical` lines._

| loop | ISPC insns / words | Zig insns / words | notes |
|---|---|---|---|
| group, N=8 / G | | | |
| sparse | | | |

## Local preview (NOT the benchmark node)

Machine: sandbox VM, `Intel(R) Xeon(R) Processor @ 2.10GHz` (AVX-512 incl. VBMI/VNNI; Zig 0.13
reports the native model as generic `x86_64` with those features), 4 vCPUs, shared and noisy.
ISPC 1.22.0 (LLVM 17.0.6, the same version as Ubuntu 24.04's package); Zig 0.13.0 official
tarball (same version as Alpine's `0.13.0-r1`). Because the node builds Zig with
`-mcpu=native` on AMD, the Zig side below was also built with `-mcpu=znver4` and `-mcpu=znver3`.
The ISPC binary is the same multi-target build; its avx512skx and avx2 paths are both in it.
Self-tests: ISPC `PRIMES_TEST=1` exits 0; Zig `PRIMES_TEST=1` all 26 lines ok. Dumping the
local builds through `dump.sh` gave `identical` for all 4 Zig functions (and `DIFFERENT` for
all 4 when pointed at a znver4 twin, so the check can fail).

Inner-loop excerpts are in `loops-local.s` (27 KB). llvm-mca (`-mcpu=znver4`, 200
iterations; only a screen: no cache, no store forwarding, Zen 5 not modelled):

| inner loop | words or ORs / iter | insns / iter | vec loads (+folded) / stores | stack reloads / iter | mca cycles / iter | mca cycles per word | per word per member |
|---|---|---|---|---|---|---|---|
| ISPC avx512skx `apply_group`, G=6 | 16 w | 76 | 14 / 2 zmm, all masked `{k}` | 9 | 13.1 | 0.82 | 0.136 |
| Zig znver4 `applyGroup` N=8 | 32 w | 105 | 20 (+16) / 4 zmm | 9 | 20.1 | 0.63 | 0.079 |
| Zig znver4 `applyGroup` N=6 | 32 w | 79 | 16 (+12) / 4 zmm | 5 | 16.1 | 0.50 | 0.084 |
| ISPC avx2 `apply_group`, G=8 | 16 w | 115 | 4 (+32) / 4 ymm | 12 | 20.1 | 1.26 | 0.157 |
| Zig znver3 `applyGroup` N=8 | 32 w | 142 | 8 (+64) / 8 ymm | 9 | 40.1 | 1.25 | 0.157 |
| ISPC avx512skx sparse (in `run_sieve`) | 8 ORs | 42 | - | 0 (+1 cmp mem) | 8.3 | 1.04 per OR | |
| Zig znver4 sparse (in `run`, unrolled x4) | 32 ORs | 155 | - | 24 | 32.4 | 1.01 per OR | |

Wall clock, same sandbox, one run each (noisy; for orientation only, local Zig build is
`-mcpu=native` = 256-bit vectors here): ISPC wheel 1T 87,718 and 102,363 passes/5 s; Zig wheel
1T 125,085.

### What differs

1. **AVX-512 group loop: the ISPC loop costs ~1.7x the Zig loop per word per member.** Three
   things stack up in `apply_group_avx512skx`:
   - *Step width.* ISPC advances 16 words per iteration (x16 gang), Zig 32 (`VW = min(8 *
     NATIVE, 32)`), so the per-member phase update (`lea/cmp/mov/cmovl/neg/add/add`, 7 scalar
     instructions in both) is paid half as often per word in Zig.
   - *Spilled row pointers.* ISPC hoisted each member's `g->buf[j]` row into its own base
     register and spilled them: every iteration reloads 6 row pointers, 2 periods and the loop
     bound from the stack (9 reloads per 16 words). Zig addresses every row off one register
     with constant displacements (`0x2240(%r11,%rdi,8)`, `0x4440(...)`, ...), so only the 8
     periods and the bound live on the stack (9 reloads per 32 words). The ISPC source comment
     says rows are read "from their fixed rows of g->buf" to avoid exactly this; on avx2 ISPC
     does use displacements (`0x468(%r8,%r15,8)`), on avx512skx it does not.
   - *Masks and G.* On AVX-512 (`TAIL_OVERRUN 0`, no `unmasked`) every load and store carries
     `{%k1}{z}` / `{%k2}` from the entry mask; Zig's are plain. And ISPC fuses G=6 on AVX-512
     against Zig's 8, so ISPC makes 8 group passes over the planes for 48 primes against Zig's 6.

   Rough size of the effect at 1M (mca cycles x iterations, ISPC 8 groups x 8 planes x 33
   iterations vs Zig 6 x 8 x 17): ~27k vs ~16k cycles per pass, about 11k cycles of a pass
   of roughly 100-150k cycles (about 50 us at 1T here). That is the right order for the 4.6%
   Zen 5 gap, if Zen 5's native Zig build also takes the 512-bit, 32-word path.
2. **AVX2 group loop: no throughput difference under mca** (1.26 vs 1.25 cycles per word,
   both bound on loads). Zig still issues fewer instructions (4.4 vs 7.2 per word) and fewer
   stack reloads (0.28 vs 0.75 per word), which a frontend- or rename-bound Zen 3 may feel and
   mca does not model; but the preview does not pin the 7.6% Zen 3 gap on this loop. Next
   suspects for Zen 3: the per-pass allocation (glibc `aligned_alloc`/`free` of ~100 KB each
   pass vs Zig's per-thread arena), and the ISPC empty-member padding (all G slots are loaded
   for a short last group; Zig specialises `applyGroup` per N). The node dump plus a perf run
   would settle it.
3. **Sparse loop: a wash.** Both are 8 independent `shlx` + `or reg,(mem)` streams per round,
   ~1 cycle per OR, store-bound. Zig unrolls x4 (32 ORs per iteration) and pays 24 stack
   reloads for it; ISPC runs 8 ORs per iteration without spills. `start_bit` and the
   per-prime set-up are both strength-reduced multiplies by the reciprocal of 30 in each.
   Tile copy favours ISPC if anything: Zig's compiler_rt `memcpy` copies byte 0 then runs
   unaligned zmm moves from offset +1, so every store splits a cache line.

Candidate experiments for the ISPC wheel (not tried here): a 32-word step on avx512skx
(two x16 vectors per iteration, one phase update), forcing displacement addressing of the
pattern rows (e.g. one `uniform` base plus constant `j * (MAXPAT + 64)` offsets inside an
`unmasked` block), and G=8 again once the per-member cost drops.
