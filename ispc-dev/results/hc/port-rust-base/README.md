# Rust base port against mike-barber's Rust: side by side

Our Rust port of the ISPC base entry is `PrimeRust/solution_9` on `hc/port-rust-base`. This note
sets it next to mike-barber's `PrimeRust/solution_1`, variant `bit-extreme-hybrid`
(`--bits-extreme`), the leading base entry in Rust. Both binaries were built here with Rust 1.97
on a 4-vCPU Intel Xeon (AVX-512) at 2.1GHz, each with its own `.cargo/config.toml`: ours
`-C target-cpu=native`, mike-barber's `target-cpu=native` with `-avx512f`. The assembly below is
from `objdump -d` of those release binaries.

Another agent ran benchmarks on the same VM during these runs, so the multi-thread figures are
noisy. One-thread figures are steadier but still only a screen; Azure decides.

## What differs

| | mike-barber `bit-extreme-hybrid` | our port (`solution_9`) |
|---|---|---|
| Dense limit | odd factors 3 to 129 | odd factors 3 to 127 |
| Dense source | a proc macro writes one `word \|= single_bit` per composite, one period of `p` words per iteration; LLVM folds them and its SLP vectoriser groups some words into vectors | const generic `P`; a const block sets each composite's single bit into a `[u64; 4]` mask table at compile time; the loop does one vector OR per four words over runs of four periods |
| Dense tail | remainder of the last period: one `if` per word with scalar ORs | same masks: whole vectors, then one to three words |
| Factor 3 | ORs into a zeroed buffer | stores its masks without loading, which initialises the buffer |
| Buffer | `vec![0; n]` (calloc, zeroed each pass) | `alloc` of 64-byte aligned, uninitialised memory; word 0 written, the rest by factor 3 |
| Sparse loop | `chunks_exact_mut(p)` over bytes, 8 relative indices, masks from `p mod 16` via const generic | raw pointer over `p`-byte chunks, 8 offsets, masks from `p mod 16` via const generic |
| Scan | `(factor/2..).find(get)`, bounds-checked `get` | same bit scan, unchecked read |
| Threads | `std::thread::spawn`, `num_cpus::get()` (affinity mask); 1, 4, n/2, n threads; sleeps 5s before each run | `std::thread::scope`, `available_parallelism()` (affinity mask); 1, n, n/2, n/4 |
| Dependencies | `num_cpus`, `structopt`, own proc-macro crate | none |

The algorithm is the same. Both clear one composite per operation in the source, both use a
dense resetter per odd factor below about 128 and a sparse byte loop with eight constant masks
above it. Our ISPC entry took the design from mike-barber and GordonBGood in the first place.

## Dense resetter, factor 47

Ours, `clear_dense::<47, false>`, run loop (unrolled four vectors, three masks hoisted into
registers):

```
vmovups -0x60(%rcx,%r9,1),%ymm3        ; 4 sieve loads
vmovups -0x40(%rcx,%r9,1),%ymm4
vmovdqu -0x20(%rcx,%r9,1),%ymm5
vmovdqu (%rcx,%r9,1),%ymm6
vorps  -0x60(%r9,%r8,1),%ymm3,%ymm3    ; OR with the mask table (one load each)
vmovups %ymm3,-0x60(%rcx,%r9,1)        ; 4 stores
...
sub    $0xffffffffffffff80,%r9
cmp    $0x5e0,%r9
jne    ...
```

Per 16 words: 15 instructions, 8 loads (4 sieve, 4 mask), 4 stores. About 0.94 instructions,
0.25 stores and 0.25 sieve loads per word.

mike-barber's `extreme_reset_047`, one period of 47 words per iteration, 11 masks in `ymm0-10`
and one in `xmm11`:

```
vmovups 0x20(%rcx),%ymm12
vorps   %ymm1,%ymm12,%ymm12
...
vorps   0x80(%rcx),%ymm4,%ymm12
vmovups %ymm12,0x80(%rcx)
...
vorps   0x160(%rcx),%xmm11,%xmm12
vmovups %xmm12,0x160(%rcx)
orb     $0x1,0x175(%rcx)               ; the 47th word: one byte RMW
add     $0x178,%rcx
cmp     $0x2e,%rsi
ja      ...
```

Per 47 words: about 41 instructions, 13 loads, 13 stores: 0.87 instructions and 0.28 stores per
word, with every mask in a register. At 47 the two loops do the same work.

## Dense resetter, factor 127

Here they part. LLVM's SLP vectoriser stops grouping mike-barber's words as the factor grows. A
crude count over the binary (vector instructions in each resetter) finds vector code in every
resetter up to 123, only a little of it at 121, and none at 125, 127 and 129. For `p > 64` a
period holds 64 composites in `p` words, at most one per word, so the scalar loop is one
read-modify-write per composite:

```
movabs $0x8000000000000000,%r11
or     %r11,(%r9)
movabs $0x4000000000000000,%r11
or     %r11,0x10(%r9)
...
orb    $0x20,0x6c(%r9)
```

`extreme_reset_127`'s loop body: 33 `or` qword, 31 `orb` and 22 `movabs` per 127-word period:
about 90 instructions, 64 loads and 64 stores (0.50 stores per word).

Ours compiles `clear_dense::<127, false>` to the same four-vector loop as 47: about 119
instructions per period, 64 loads (32 sieve, 32 mask) and 32 stores (0.25 stores per word). It
runs more instructions than mike-barber's scalar code but half the stores, and the dense loops
are store-bound.

## Sparse loop

Ours (inlined into `Sieve::run`; LLVM unrolled it twice and ran short of registers for the second
copy's offsets):

```
orb    $0x8,(%r9,%r14,1)
orb    $0x4,(%r9,%r8,1)
...                                    ; 8 orb, first chunk
orb    $0x8,(%r9,%rbx,1)
lea    0x1(%r12,%r8,1),%r13
orb    $0x4,(%r9,%r13,1)
...                                    ; 8 orb + 7 lea, second chunk
add    %r10,%r9
add    %r10,%r9
add    $0xfffffffffffffffe,%rdx
jne    ...
```

27 instructions per 16 composites: 1.7 per composite, one byte load and one byte store each.

mike-barber's (inlined into `run_implementation_st`): eight pointers, one per offset, each bumped
by `p` every chunk:

```
orb    $0x10,(%rbx,%rax,1)
orb    $0x20,0x0(%rbp,%rax,1)
...                                    ; 8 orb
sub    %r15,%r12
add    %r13,%rdx                       ; 8 pointer bumps
...
add    %r13,%rbx
cmp    %r12,%r14
jb     ...
```

19 instructions per 8 composites: 2.4 per composite, the same one load and one store each. Both
are at the base rules' floor for memory traffic; ours issues about 30% fewer instructions.

## Measured locally

Passes in 5 seconds, interleaved, two rounds (ISPC base built with `build.sh`; mike-barber run as
`--bits-extreme -t 1` and `-t 4`):

| | 1 thread | 4 threads |
|---|---|---|
| ISPC base (`PrimeISPC/solution_2`) | 44,317 / 52,168 | 176,254 / 149,164 |
| Rust port (`PrimeRust/solution_9`) | 50,552 / 49,874 | 108,882 / 205,055 |
| mike-barber `bit-extreme-hybrid` | 47,005 / 48,049 | 135,042 / 100,501 |

The four-thread column swings by a factor of two between rounds, so it says nothing. At one
thread the port is about 5% ahead of mike-barber's code here.

Two differences isolated by building a variant and running it interleaved with the port:

- Dense tail. An earlier build of the port cleared the words after the last four-period run with
  one scalar single-bit OR per composite, the way the ISPC entry does; LLVM unrolled that loop
  only four times and computed each mask with a shift. Taking whole vectors from the same mask
  table instead raised the port from 49,818 / 50,559 to 56,034 / 53,016 passes at one thread
  (about +8%).
- Buffer set-up. A variant that allocates a zeroed buffer (`alloc_zeroed`, as mike-barber's
  `vec![0; n]` does) and runs factor 3 as an ordinary read-modify-write pass ran 51,212 /
  50,358 / 47,639 passes at one thread, against 55,635 / 51,620 / 51,849 for the port in the
  same three interleaved rounds. Every port round beat every zeroed round; the medians differ
  by about 3%. The ISPC entry measured about 1% for the same change on Azure.

## New solution, or improvements for mike-barber?

Improvements for mike-barber. The port has the same four characteristics as `PrimeRust/solution_1`
(base, faithful, parallel, one bit) in the same language, and CONTRIBUTING.md asks that such work
go to the existing solution first. The design is his and GordonBGood's: dense resetters per
factor, a byte loop with eight constant masks, one sieve per thread. What the port adds is three
contained changes, each a few dozen lines in his `unrolled_extreme.rs` or `main.rs`: explicit
`[u64; 4]` vectors in the dense resetters, so factors 125 to 129 (and most of 121's words)
stop falling back to one store per composite; factor 3 initialising an uninitialised buffer instead of a calloc and a
read-modify-write pass (about 3% here); and a vector tail on the same masks. The sparse loop
issues fewer instructions in ours but makes the same memory traffic, so it is the least likely
to show on the clock. Before offering them, measure each change inside his code on Azure
(Zen 3 and Zen 5, five rounds) against his unmodified build: the local one-thread lead of about
5% is a screen on a shared VM, and his `-avx512f` build flag and five-second sleeps between runs
are left as they are. A separate solution would be hard to justify unless his repository is
closed to changes.
