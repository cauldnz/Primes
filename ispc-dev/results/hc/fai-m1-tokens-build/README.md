# fai-m1: source size in tokens, and build times on the container

Run 11, a measurement made by a background agent in about 5 minutes (89k tokens, 28 tool
calls). It gives evidence for claim 4 (token efficiency) and claim 2 (fast tooling). The
scripts are `count.py` (token counts) and `t3.sh` (timings).

## Source size

The tokenizer is `tiktoken` 0.14.0 with the `o200k_base` encoding; `cl100k_base` is shown as a
cross-check. "nbnc" means lines that are neither blank nor comment. "o200k, no comments" is the
o200k count after removing comments and blank lines.

| Source | bytes | lines | nbnc | o200k | o200k, no comments | cl100k |
|---|---:|---:|---:|---:|---:|---:|
| Fai `Primes.fai` (`hc/fai-champion` 1ce921d), full | 9,647 | 277 | 210 | 2,945 | 2,417 | 2,929 |
| Fai, without the `example`/`forall` lines | 8,693 | 253 | 186 | 2,595 | 2,067 | 2,579 |
| Fai, also without the definitions only contracts use | 7,878 | 231 | 172 | 2,339 | 1,881 | 2,323 |
| plain OCaml `primes.ml` (`hc/ocaml-final` solution_4) | 12,512 | 326 | 250 | 4,229 | 3,056 | 4,226 |
| ISPC `primes_base.ispc` (`hc/ispc-landing-4` solution_2; the whole program) | 25,453 | 510 | 375 | 7,620 | 5,436 | 7,639 |
| Rust mike-barber `src/` (3 files, all variants and tests) | 63,210 | 1,708 | 1,234 | 14,549 | 10,189 | 14,541 |
| Rust, the bit-extreme-hybrid slice (approximate, undercounts) | 17,363 | 512 | 355 | 4,069 | 2,788 | 4,059 |

Notes on the counts:
- **The designs differ.** On these figures the Fai source is the smallest, but it is a plain
  one-bit-at-a-time loop. The OCaml, ISPC and Rust sources carry dense and sparse pattern
  code. The like-for-like comparison is the Fai port of the OCaml design (fai-003), counted the
  same way once it exists.
- **What the Rust slice covers.** It is `unrolled_extreme.rs`, the patterns module and the
  sparse resetter of `unrolled.rs`, and the helper-macros crate. It leaves out the shared sieve
  trait and the runner.

## Build times

The container is an Intel Xeon at 2.10 GHz with 4 vCPUs. Each time is the median of 3 runs.
Every build passed `PRIMES_TEST=1`. One process from another job used about one core
throughout, so treat these as rough.

| Command | median (s) |
|---|---:|
| `fai check Primes.fai` | 0.215 |
| `fai test Primes.fai` (24 contracts) | 0.233 |
| `sh build.sh` (`fai build --no-daemon --release`, native, with the `cc` link) | 0.424 |
| `fai build` with a daemon started | 0.385 |
| OCaml 5.2.0 flambda `ocamlopt -O3 -unsafe -inline 200` (solution_4, with link) | 0.262 |
| OCaml 5.2.0 flambda, type-check only (`-stop-after typing`) | 0.030 |
| OxCaml 5.2.0+ox (flambda2), same flags | 0.455 |
| OxCaml, type-check only | 0.081 |

Notes on the timings:
- **No speed advantage for Fai.** On one source file of this size the Fai toolchain is not
  faster than the OCaml compilers. A native build is 0.42 s against 0.26 s for OCaml and
  0.46 s for OxCaml. A check is 0.22 s against 0.03 s for an OCaml type-check, though
  `fai check` also runs the `example` contracts.
- **What made run 10 slow.** Its cycles were slower because of the Docker and opam builds,
  not the compiler.
- **The daemon.** After builds with a daemon started, `fai daemon status` still reported 0
  commands served. In 0.1.0, `fai build` may not use the daemon.
