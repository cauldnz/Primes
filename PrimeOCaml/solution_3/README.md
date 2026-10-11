# OxCaml solution by cauldnz

![Algorithm](https://img.shields.io/badge/Algorithm-base-green)
![Faithfulness](https://img.shields.io/badge/Faithful-yes-green)
![Parallelism](https://img.shields.io/badge/Parallel-yes-green)
![Bit count](https://img.shields.io/badge/Bits-1-green)

A sieve of Eratosthenes that follows the base algorithm, built with [OxCaml](https://oxcaml.org), Jane Street's branch of the OCaml compiler with the flambda2 optimiser. It starts from the plain OCaml 5.2 port in [PrimeOCaml/solution_4](../solution_4) and uses one OxCaml extension where it pays: 256-bit vectors in the dense loop on x86-64. There are no libraries beyond the standard library and `unix` (for the clock). It is the design of the author's ISPC base entry ([PrimeISPC/solution_2](../../PrimeISPC/solution_2)) and its Rust port ([PrimeRust/solution_9](../../PrimeRust/solution_9)). That design follows mike-barber's Rust entry ([PrimeRust/solution_1](../../PrimeRust/solution_1)) and GordonBGood's Chapel entry ([PrimeChapel/solution_1](../../PrimeChapel/solution_1)).

## Implementation

### Storage

One bit per odd number: bit `i` stands for `2i + 1`, and a set bit means composite. The sieve is a `Bytes` buffer, read and written as 64-bit little-endian words through the compiler primitives `%caml_bytes_get64u` and `%caml_bytes_set64u`, or as single bytes. The buffer is not zeroed. `create` writes word 0, so the scan can read the bit for 3. The scan always finds 3 first, and the pass for 3 stores every word without reading it, which initialises the rest of the buffer.

### The base algorithm

An outer loop scans the odd numbers from 3 for the next clear bit, then clears that factor's odd multiples, stepping `2 × factor` through the numbers. It stops at the square root of the sieve size. Every composite gets its own single-bit OR.

- **Factors below 128.** The odd multiples of `p` repeat every `p` 64-bit words, 64 multiples to a period. For each factor, the sieve builds the pattern of four periods (`4p` words) in a scratch buffer it owns, setting each of the 256 multiples with its own single-bit OR. That is what the Rust port's compile-time masks hold; OCaml has no const generics, so the pattern is built at run time, once per factor per pass. Clearing then ORs the pattern into the sieve 32 bytes per loop step, starting at the period that holds `p²`. On x86-64 that step is one 256-bit load, `vorps` and store, written with OxCaml's `int64x4` vector type (`amd64/dense.ml`). That loop ORs two consecutive runs of the pattern per pass, so each pattern vector is loaded once for two sieve words. OxCaml's vector types exist only on x86-64, so on other machines `build.sh` takes `scalar/dense.ml`, which does the step as eight 32-bit word ORs (`%caml_bytes_get32u` and `%caml_bytes_set32u`), two per 64-bit word. On Arm, OCaml 5 emits a `dmb ishld` barrier before every 64-bit integer store to a `Bytes` buffer, as part of its memory model; 32-bit stores do not get one. Building the pattern is the same on both: one single-bit OR per multiple (into a 32-bit word in `scalar/dense.ml`, a 64-bit word in `amd64/dense.ml`; on a little-endian machine the bit layout is the same). The smaller multiples in that period are composite too; only `p` itself is restored afterwards. Every odd factor takes the same path, including 9, 15 and the other composites, so nothing beyond 2 being the only even prime is assumed.
- **Factors of 128 and above.** The same idea over bytes: eight multiples repeat every `p` bytes, each at a fixed bit position. Their byte offsets and masks are computed once per factor. A loop walks over the `p`-byte chunks, so each composite is one OR of a single-bit mask. Like the dense loop, this one is picked per architecture by `build.sh`. On x86-64 (`amd64/sparse.ml`) the mask is ORed into the unaligned 64-bit word that starts at the composite's byte, with the mask in the low byte, so the other seven bytes are ORed with zero. For `p` of 128 and above that word stays inside the chunk; the partial last chunk uses byte ORs. Other machines (`scalar/sparse.ml`) use a byte OR throughout, because the 64-bit word form was 28% slower on Arm Neoverse N2.

The inner loops use only integer arithmetic, the unboxed 64-bit primitives and, on x86-64, the vector primitives. The generated assembly (`ocamlopt -S`) shows no heap allocation and no boxed `Int64` in them; the only calls are the OCaml 5 safepoint polls on loop back edges. The build uses `-unsafe`, so `Bytes` accesses carry no bounds checks; a test against a plain sieve for every size from 1 to 20,000, and every 997th up to 2,000,000, passed.

### OxCaml extensions

The vector OR is declared as a compiler builtin (`external vor : int64x4 -> int64x4 -> int64x4 = "caml_vec256_unreachable" "caml_avx_vec256_or" [@@builtin]`), and the loads and stores use the primitives `%caml_bytes_getu256u` and `%caml_bytes_setu256u`. `ocamlopt` emits the instructions inline, but still lists the builtin's C name among the program's symbols, so `amd64/simd_stubs.c` defines it as a function that aborts and is never called. OxCaml enables AVX2 by default when the compiler itself was built on an AVX2 machine.

On a shared 4-vCPU Intel Xeon container, three interleaved 5-second one-thread runs gave:

| build | passes |
|---|---|
| plain source, OxCaml `-O3` | 18,980, 17,872, 17,807 |
| 128-bit vectors (two per step) | 23,180, 22,472, 22,586 |
| 256-bit vectors (this version) | 25,999, 25,404, 26,100 |

On x86-64 the copy loops and the sparse loop keep their byte offsets as untagged 64-bit integers (`int64#`) and use the primitives indexed by them (`%caml_bytes_getu256u_indexed_by_int64#`, `%caml_bytes_get64u#_indexed_by_int64#` and their `set` forms). With tagged `int` offsets every access first shifts the tag off the index, and a byte OR also retags and untags the byte. OxCaml has no byte access indexed by an untagged integer, which is why the x86-64 sparse loop ORs a 64-bit word. Instructions per unit in the `-S` listing (loop overhead and the safepoint poll included):

| loop | tagged `int` | `int64#` |
|---|---|---|
| sparse, per composite | 7.75 | 5.5 |
| dense OR, x86-64, per 32 bytes | 13 | 10 |
| dense store (factor 3), x86-64, per 32 bytes | 11 | 8 |

The sparse loop has 20 values live, more than the 13 registers the allocator uses, so six of the eight offsets and six of the eight masks still come from the stack. Three interleaved 5-second one-thread runs on the same kind of container: tagged 26,150, 26,498, 26,494 passes; `int64#` 29,510, 28,285, 29,573. The `scalar/` modules keep tagged `int` offsets and byte ORs.

### Faithfulness

All of a sieve's state lives in the `sieve` record: the bit buffer and the pattern scratch. Every pass creates a new record, which allocates both buffers at run time, sized from the sieve size. Nothing is carried from one pass to the next, and no external code does any sieving.

### Parallelism

The multi-threaded runs start one domain per thread with `Domain.spawn`, each running its own sieves until the 5 seconds are up; the passes are summed. The program reports one domain, then all hardware threads (`Domain.recommended_domain_count`), then exactly four when the machine has more than four.

Each pass allocates a 62.5KB sieve and drops it, while almost nothing stays live, so with OCaml's default settings the major GC finishes a cycle every few passes, and each cycle stops every domain. For the multi-domain runs the program raises the GC's space overhead from 80 to 1,000, which makes cycles rare. The one-domain run keeps the default, which was about 10% faster there.

## How this was built

This solution came out of the same experiment in agentic engineering with Claude (Anthropic) as the author's ISPC entries. A Claude Code session ported the design, wrote the self-test and ran the benchmarks; the author set the brief and made the calls.

## Run instructions

### Docker

The `Dockerfile` builds on `oxcaml:5.2.0-ox`, an image with Ubuntu 24.04 and the OxCaml switch `5.2.0+ox` on `PATH`. No public registry hosts that image. `Dockerfile.standalone` builds the same switch from the OxCaml opam repository first, which takes a long time, then the solution:

```
docker build -f Dockerfile.standalone -t primes-oxcaml-base .
docker run --rm primes-oxcaml-base
```

Both run the binary on plain `ubuntu:24.04`. OxCaml needs glibc, so there is no Alpine build.

### Native

With the OxCaml switch (`opam switch create 5.2.0+ox --repos ox=git+https://github.com/oxcaml/opam-repository.git,default`):

```
sh build.sh
./primes
```

`build.sh` picks `amd64/` or `scalar/` from `uname -m` and runs `ocamlopt -O3 -unsafe -I +unix -I <dir> unix.cmxa [amd64/simd_stubs.c] <dir>/dense.ml primes.ml -o primes`, plus two `-alert` flags that silence OxCaml's warnings about `Domain.spawn` (it prefers its own threading library; this program spawns no more domains than `Domain.recommended_domain_count`). `-O2`, `-O3 -inline 200` and `-O3` with `-flambda2-join-points -flambda2-result-types-all-functions` all produced the same object file as `-O3` for the plain source.

`PRIMES_TEST=1 ./primes` checks the prime count for every power of ten from 10 to 10⁸ and some edge cases, prints the results and exits non-zero on any mismatch.

## Output

Intel Xeon, 4 vCPUs, a shared development container with other work running, native build with OxCaml 5.2.0+ox and 256-bit vectors:

```
cauldnz-oxcaml-base;25404;5.000146;1;algorithm=base,faithful=yes,bits=1
cauldnz-oxcaml-base;62022;5.000584;4;algorithm=base,faithful=yes,bits=1
```

Self-test:

```
size 1 -> 0 primes (expected 0) 1
size 2 -> 1 primes (expected 1) 1
size 3 -> 2 primes (expected 2) 1
size 10 -> 4 primes (expected 4) 1
size 100 -> 25 primes (expected 25) 1
size 1000 -> 168 primes (expected 168) 1
size 10000 -> 1229 primes (expected 1229) 1
size 100000 -> 9592 primes (expected 9592) 1
size 1000000 -> 78498 primes (expected 78498) 1
size 10000000 -> 664579 primes (expected 664579) 1
size 100000000 -> 5761455 primes (expected 5761455) 1
size 127 -> 31 primes (expected 31) 1
size 16383 -> 1900 primes (expected 1900) 1
```
