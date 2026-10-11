# OxCaml solution by cauldnz

![Algorithm](https://img.shields.io/badge/Algorithm-base-green)
![Faithfulness](https://img.shields.io/badge/Faithful-yes-green)
![Parallelism](https://img.shields.io/badge/Parallel-yes-green)
![Bit count](https://img.shields.io/badge/Bits-1-green)

A sieve of Eratosthenes that follows the base algorithm, built with [OxCaml](https://oxcaml.org), Jane Street's branch of the OCaml compiler with the flambda2 optimiser. The source is the same plain OCaml 5.2 as [PrimeOCaml/solution_4](../solution_4), with no libraries beyond the standard library and `unix` (for the clock); only the label and the opening comment differ. This entry measures what the compiler alone does for that code. It is the design of the author's ISPC base entry ([PrimeISPC/solution_2](../../PrimeISPC/solution_2)) and its Rust port ([PrimeRust/solution_9](../../PrimeRust/solution_9)), written as ordinary OCaml. That design follows mike-barber's Rust entry ([PrimeRust/solution_1](../../PrimeRust/solution_1)) and GordonBGood's Chapel entry ([PrimeChapel/solution_1](../../PrimeChapel/solution_1)).

## Implementation

### Storage

One bit per odd number: bit `i` stands for `2i + 1`, and a set bit means composite. The sieve is a `Bytes` buffer, read and written as 64-bit little-endian words through the compiler primitives `%caml_bytes_get64u` and `%caml_bytes_set64u`, or as single bytes. The buffer is not zeroed. `create` writes word 0, so the scan can read the bit for 3. The scan always finds 3 first, and the pass for 3 stores every word without reading it, which initialises the rest of the buffer.

### The base algorithm

An outer loop scans the odd numbers from 3 for the next clear bit, then clears that factor's odd multiples, stepping `2 × factor` through the numbers. It stops at the square root of the sieve size. Every composite gets its own single-bit OR.

- **Factors below 128.** The odd multiples of `p` repeat every `p` 64-bit words, 64 multiples to a period. For each factor, the sieve builds the pattern of four periods (`4p` words) in a scratch buffer it owns, setting each of the 256 multiples with its own single-bit OR. That is what the Rust port's compile-time masks hold; OCaml has no const generics, so the pattern is built at run time, once per factor per pass. Clearing then ORs the pattern into the sieve one word at a time, four words per loop step, starting at the period that holds `p²`. The smaller multiples in that period are composite too; only `p` itself is restored afterwards. Every odd factor takes the same path, including 9, 15 and the other composites, so nothing beyond 2 being the only even prime is assumed.
- **Factors of 128 and above.** The same idea over bytes: eight multiples repeat every `p` bytes, each at a fixed bit position. Their byte offsets and masks are computed once per factor. A loop walks over the `p`-byte chunks, so each composite is one byte OR.

The inner loops use only `int` arithmetic and the unboxed 64-bit primitives. The generated assembly (`ocamlopt -S`) shows no heap allocation and no boxed `Int64` in them; the only calls are the OCaml 5 safepoint polls on loop back edges. The build uses `-unsafe`, so `Bytes` accesses carry no bounds checks; a test against a plain sieve for every size from 1 to 20,000, and every 997th up to 2,000,000, passed.

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

`build.sh` runs `ocamlopt -O3 -unsafe -I +unix unix.cmxa primes.ml -o primes`, plus two `-alert` flags that silence OxCaml's warnings about `Domain.spawn` (it prefers its own threading library; this program spawns no more domains than `Domain.recommended_domain_count`). `-O2`, `-O3 -inline 200` and `-O3` with `-flambda2-join-points -flambda2-result-types-all-functions` all produce the same object file as `-O3` for this source.

`PRIMES_TEST=1 ./primes` checks the prime count for every power of ten from 10 to 10⁸ and some edge cases, prints the results and exits non-zero on any mismatch.

## Output

Intel Xeon, 4 vCPUs, a shared development container with other work running, native build with OxCaml 5.2.0+ox:

```
cauldnz-oxcaml-base;17028;5.000096;1;algorithm=base,faithful=yes,bits=1
cauldnz-oxcaml-base;53356;5.000743;4;algorithm=base,faithful=yes,bits=1
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
