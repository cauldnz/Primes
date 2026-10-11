# ox-005: where the OxCaml champion spends its cycles

Subject: `PrimeOCaml/solution_3` at cbcd24d (branch `hc/oxcaml-champion`): the OxCaml base with
the 256-bit dense pattern copy (`amd64/dense.ml`) and the scalar fallback (`scalar/dense.ml`).
Built with OxCaml 5.2.0+ox, the flags of `build.sh`.

Machine: a shared 4-vCPU cloud container, Intel Xeon at 2.8GHz (TSC 2.8GHz), not Zen. `perf`
does not work here, so the numbers come from rdtsc timers in a diagnostic build
(`primes_diag.ml` and `rdtsc_stub.c`, this folder; not for submission). It is the same sieve
code with timers around each phase. The one other change: `dense_limit` is read from the
environment (`DENSE_LIMIT`, default 128), so it is no longer a compile-time constant.

Method: 10,000 passes after 200 warm-up passes, one thread. The cost of each rdtsc pair (30-34
cycles) is taken out. Three interleaved rounds of the AVX build and the scalar build.

## Phases, one thread, AVX build (the one that runs on x86-64)

| Phase | Round 1 | Round 2 | Round 3 | Share |
|---|---:|---:|---:|---:|
| setup (create: Bytes.create of the sieve and the pattern buffer) | 7,100 | 7,200 | 7,100 | 1.3% |
| dense pattern build (30 factors) | 46,000 | 45,900 | 42,100 | 8.6% |
| dense copy (OR runs, partial run, restore p) | 186,300 | 184,600 | 170,900 | 34.6% |
| sparse (137 factors, 128 and up) | 265,500 | 264,000 | 245,100 | 49.6% |
| next-prime scan | 5,400 | 5,600 | 5,800 | 1.1% |
| total, cycles per pass | 536,200 | 532,800 | 494,600 | |
| total, us per pass | 191.5 | 190.3 | 176.6 | |

Cycles per pass. Shares are from round 2; the three rounds give the same shares within 0.2
points. The phases add up to about 95% of the total; the rest is the loop and timer code
between them and the first-pass `count_primes` spread over the passes.

Per unit of work: 234,400 dense words a pass at 0.73-0.80 cycles each, and 133,500 sparse
marks at 1.84-1.99 cycles each. The pattern build sets 7,680 bits a pass (30 factors times
256) at about 6 cycles per bit, including the `Bytes.fill` of the buffer.

GC per pass: 6 minor words, 8,337 major words, 0.08 minor and 0.04 major collections.

## Scalar build, same rounds

| Phase | Round 1 | Round 2 | Round 3 | Share |
|---|---:|---:|---:|---:|
| setup | 8,500 | 8,600 | 9,200 | 1.1% |
| dense pattern build | 44,900 | 47,200 | 43,800 | 5.9% |
| dense copy | 420,800 | 445,700 | 418,900 | 55.4% |
| sparse | 262,600 | 269,500 | 258,100 | 33.5% |
| scan | 5,800 | 5,700 | 5,800 | 0.7% |
| total | 767,500 | 804,100 | 760,800 | |

The scalar copy costs 1.8-1.9 cycles per word, close to the plain OCaml line in ocaml-003
(2.0). The AVX copy is 2.3-2.4 times faster per word here and takes the whole pass down by
about 30%.

## What this says

- With the 256-bit copy, sparse is now the largest phase: half the pass, against a third of the
  dense copy. Before the copy (scalar build, and ocaml-003) it was the other way round.
- The pattern build is 8.6% and the same in both builds. It is one single-bit OR per composite
  of the 4p-word pattern, so it is the floor of the faithful dense path, apart from the
  `Bytes.fill`.
- Setup and scan are under 2.5% together. Nothing to win there.
- So the next gains are in the sparse loop (about 2 cycles per mark, which is the same as the
  plain line's 2.3) and in moving work between sparse and dense by the dense limit.

## Dense limit, diagnostic build

Two interleaved rounds of 5,000 passes with `DENSE_LIMIT` set (AVX build), total cycles per
pass. Round 1 had a slow 128 sample (756k against 529k in round 2); the box is noisy.

| Limit | Round 1 | Round 2 | Pattern build | Dense copy | Sparse (round 2) |
|---:|---:|---:|---:|---:|---:|
| 64 | 573,600 | 623,200 | 29,100 | 125,000 | 426,700 |
| 96 | 556,500 | 533,800 | 35,600 | 142,600 | 314,700 |
| 128 | 756,300 | 528,600 | 45,400 | 184,900 | 259,900 |
| 160 | 543,000 | 527,400 | 55,500 | 215,200 | 218,000 |
| 192 | 662,500 | 569,100 | 65,400 | 266,100 | 196,500 |
| 256 | 721,700 | 603,900 | 82,100 | 334,600 | 145,400 |

The total is flat from 96 to 160 within the noise here; 64 and 192 and up are worse. The
sweep on the real build is in ox-006 (`hc/ox-006-limit`).

## Reproducing

In a scratch copy of `PrimeOCaml/solution_3`, with the two files from this folder copied in:

    ocamlopt -O3 -unsafe -alert -do_not_spawn_domains -alert -unsafe_multidomain \
      -I +unix -I amd64 unix.cmxa amd64/simd_stubs.c rdtsc_stub.c amd64/dense.ml \
      primes_diag.ml -o diag_avx
    ocamlopt -O3 -unsafe -alert -do_not_spawn_domains -alert -unsafe_multidomain \
      -I +unix -I scalar unix.cmxa rdtsc_stub.c scalar/dense.ml primes_diag.ml -o diag_scalar
    ./diag_avx; PASSES=5000 DENSE_LIMIT=160 ./diag_avx

Both builds pass `PRIMES_TEST=1`.
