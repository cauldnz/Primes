# Generalising the ISPC design to other languages

A record per language of what carried over from the ISPC entries (wheel: `PrimeISPC/solution_1`;
base: `PrimeISPC/solution_2`), kept for the write-up. Numbers are passes per second per thread at
one thread, median of 6 paired rounds, from the final scoreboard of run ap-20261011T0645Z.

## Run ap-20261011T1929Z (12 October): OxCaml

The first climb in a language none of our entries used. Two lines ran side by side from the
same design, our ISPC base: OxCaml (`PrimeOCaml/solution_3`) and plain OCaml 5.2 with flambda
(`PrimeOCaml/solution_4`) as the control. Per-change numbers are from the ledger's `r10-` rows;
the gaps are from the final scoreboard.

| Language | Experiments decided | Kept | Gap to ISPC at 1T, Zen 5 / Zen 3 | What carried over | What did not |
|---|---|---|---|---|---|
| OxCaml base (PrimeOCaml/solution_3) | 16 (+ 7 measurements) | 9 in the champion (one a merge); 1 more kept alone but lost when merged | 0.52 / 0.62 (Cobalt 0.28) | 256-bit dense copy (ISPC hc-002); two runs per step (from the plain line) | the x86 sparse and untagged forms on Arm (−28% on Cobalt); two runs per step on Arm (−0.4%) |
| OCaml base (PrimeOCaml/solution_4) | 6 (+ 2 measurements) | 1 | 0.24 / 0.30 (Cobalt 0.08) | the design itself; two runs per step | GC space overhead from the start (−3.0% ± 3.9 at 1T on Zen 5); 32-bit stores everywhere (−38% on x86 locally); dense limit 64 or 96; an `Int64` Bigarray sieve (about −8%) |

### Set-up cost

- Harness: two new kinds in `hc-pool.sh`, about 60 lines. `oxbuild` builds the toolchain image
  on a node, times it and saves it to storage; `ocaml` benches candidate and champion from that
  image against gkpotter's two entries and our ISPC base.
- Toolchain: the `5.2.0+ox` switch built in 347 s on Zen 5 (16 vCPU) and 604 s on Cobalt; the
  whole image took 561 s and 775 s. Each image is 1.2GB with zstd. A pool then loads the image
  in minutes, and a pre-empted node does not rebuild.
- Local: the same switch took 1,183 s on the 4-vCPU development container, with two source
  tarballs rebuilt by hand because its proxy refuses GitHub archive URLs.
- The plain-OCaml line needed no toolchain work: the official `ocaml/opam` flambda image.

### Experiments and keeps

OxCaml, at 1T against the version before (Zen 5 / Zen 3):

- Kept: 256-bit dense copy, +60.5% / +41.4%; x86-only untagged `int64#` addressing with a
  64-bit-word sparse OR, +26.6% / +17.4%; constant masks in the x86 sparse loop, +5.8% /
  +12.6%; two runs per step in the x86 dense copy, +7.5% / +4.8%, merged with the constant
  masks for +7.7% / +4.2%; the pattern build with 256-bit zeroing and untagged ORs, +3.3% /
  +7.4%. Two runs per step in the 256-bit copy (+4.6% / +3.1%) was kept and then folded into
  the x86 kernel. Four runs per step was kept on its own (+3.1% / +1.3% at 4T) but lost 1.2% at
  4T on Zen 3 when merged with the pattern-build change, so it is not in the champion.
- Arm (decided on Cobalt; x86 binaries identical): 32-bit stores in the dense copy and pattern
  build, +61.4% at 1T.
- Reverted at the Cobalt gate: untagged addressing in shared code (+22.1% on Zen 5, −27.9% on
  Cobalt) and constant-mask sparse in shared code (+32.8% on Zen 5, −27.6% on Cobalt). Both
  came back as x86-only kernels.
- Reverted or rejected: two runs per step in the Arm dense copy (−0.4% on Cobalt); 16- or
  32-bit sparse ORs (−7.0% and −5.8% locally); two sparse chunks per loop step (−1.5%
  locally).
- Measurements: the toolchain build; the probe of SIMD widths, unboxed types, locals and
  domains (`ocaml/OXCAML-NOTES.md`); the plain source compiled by OxCaml (−4.1% on Zen 5,
  +8.4% on Zen 3, +163% on Cobalt against the plain line).

Plain OCaml: one keep, two runs per step in the dense OR (+7.3% / +8.5%, +23.3% on Cobalt).
The GC change, the two dense limits and the Bigarray sieve were dropped. A profile on the
local Xeon put 54% of the pass in the dense OR and 36% in sparse.

### The plain-OCaml vs OxCaml gap

At 1T, OxCaml over plain OCaml: 2.19 on Zen 5 (72.2k against 32.9k), 2.04 on Zen 3 (37.2k
against 18.2k), 3.45 on Cobalt (11.8k against 3.4k). At 4T: 2.16 on Zen 5 and 1.99 on Zen 3. The compiler alone was worth little on x86 (−4% to +8%). On x86 nearly all of
the gap comes from three OxCaml features in the x86 kernel: 256-bit vectors, untagged `int64#`
offsets and `let mutable` counters that hold them. `local_` allocation and
`Domain.Safe.spawn` played no part: the loops allocate nothing.

### What transferred and what was new

From the ISPC, Rust and Zig climbs: the vector dense copy (ISPC hc-002, the largest single
gain here) and the two-run copy, which the plain line found and OxCaml borrowed. The base design
itself carried over unchanged, as it did for C++, Rust and Zig.

New in this climb:

- Per-architecture kernels. Two changes won 22% to 33% on Zen 5 and lost 28% on Cobalt in
  shared code. Splitting the dense and sparse loops into `amd64/` and `scalar/`, picked by
  `build.sh`, kept the x86 gains and left Arm byte-identical. No earlier climb needed this.
- Constant-mask sparse. Taking a chunk's eight composites in bit order makes every mask a
  constant, so only eight offsets stay live and the loop fits in registers.
- Untagged addressing. OCaml's tagged integers cost two shifts per access; `int64#` offsets
  removed them. This is OCaml-specific, as were Rust's hoisted bounds checks.

### The Arm finding

On Cobalt the scalar dense copy was 80% of the pass (561 us of 699). It does not allocate. The
compiled loop shows why: OCaml 5 puts a `dmb ishld` barrier before every 64-bit integer store on
Arm, whatever the container (Bytes, Bigarray, bigstring, `int64#` arrays all cost about 18.9 us
per 62.5 KB copy). 32-bit stores don't get the barrier (6.2 us), nor do float stores (2.0 us,
but only through a cast we would not ship). Switching the Arm copy to 32-bit stores gave +61%,
and the same barrier is the likeliest reason plain OCaml is 12 times behind Rust on Cobalt
against 4 times on Zen. This is a finding worth taking to the OCaml developers. OxCaml's SIMD
extension does not support Arm yet, so Arm still has the most left.

Node-minutes are again not separable by line from `results/cost-log.csv`.

## Run ap-20261011T0645Z (11 October)

| Language | Experiments decided | Kept | Gap to ISPC at 1T, Zen 5 / Zen 3 | What carried over | What did not |
|---|---|---|---|---|---|
| C++ wheel (PrimeCPP/solution_7) | 2 | 0 | −14% / +7% | the design itself; clang over GCC (run 8) | ISPC's one-base-pointer group loop (+7.7% Zen 5, −2.8% Zen 3) |
| C++ base (PrimeCPP/solution_6) | 2 (+ gate check) | 1 | 0% / −8% | the 512-bit dense routines on Zen 5 only (CPUID family 1Ah) | |
| Rust wheel (PrimeRust/solution_8) | 5 (incl. a profile) | 3 | −6% / −5% | pattern build without a bit loop; bounds checks hoisted out of the group loop (raw pointers inside) | |
| Rust base (PrimeRust/solution_9) | 1 | 0 | −11% / −14% | AVX-512 off (run 8) | dense phase with masks in registers (flat) |
| Zig base (PrimeZig/solution_4) | 3 | 1 | −9% / 0% | the pass for 3 initialises the sieve | a twice-wide dense step on Zen 5 (−8.9%: Zig 0.13 emits no 512-bit code there); the evex512 build flag (no change, unverified) |
| Zig wheel (PrimeZig/solution_4) | 3 | 3 | −5% / +4% | the 7×11 tile and 13 in one pass; comptime tables (permitted, +16%) | |

Gaps: what generalises easily is the algorithmic shape (planes, tile, groups, tables). What does
not is the code generation ISPC gets for free: Rust needed its bounds checks hoisted by hand
(170 → 93 instructions per 32 words), and the Zen 5 512-bit gains depend on each compiler emitting
512-bit code there at all (C++ yes with `-march=native`; Zig 0.13 no).

Node-minutes per language are not separable from `results/cost-log.csv`, which is kept per pool,
not per task; about 6 rounds × 2 chips per experiment throughout.
