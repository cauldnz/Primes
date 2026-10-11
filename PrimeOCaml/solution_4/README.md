# OCaml solution by cauldnz

![Algorithm](https://img.shields.io/badge/Algorithm-base-green)
![Faithfulness](https://img.shields.io/badge/Faithful-yes-green)
![Parallelism](https://img.shields.io/badge/Parallel-yes-green)
![Bit count](https://img.shields.io/badge/Bits-1-green)

A sieve of Eratosthenes that follows the base algorithm, in plain OCaml 5.2 built with the flambda optimiser. It uses only the standard library and `unix` (for the clock), and one source file serves every architecture.

The design is that of the author's ISPC base entry ([PrimeISPC/solution_2](../../PrimeISPC/solution_2)) and its Rust port ([PrimeRust/solution_9](../../PrimeRust/solution_9)). That design follows mike-barber's Rust entry ([PrimeRust/solution_1](../../PrimeRust/solution_1)) and GordonBGood's Chapel entry ([PrimeChapel/solution_1](../../PrimeChapel/solution_1)). [PrimeOCaml/solution_3](../solution_3) is the same program built with OxCaml, with vector and untagged-integer kernels on x86-64.

The output label is `cauldnz-ocaml-base`, with the tags `algorithm=base,faithful=yes,bits=1`.

## Implementation

### Storage

One bit per odd number: bit `i` stands for `2i + 1`, and a set bit means composite. The sieve is a `Bytes` buffer, read and written as 64-bit little-endian words through the compiler primitives `%caml_bytes_get64u` and `%caml_bytes_set64u`, or as single bytes.

The buffer is not zeroed. `create` writes word 0, so the scan can read the bit for 3. The scan always finds 3 first, and the pass for 3 stores every word without reading it. That pass initialises the rest of the buffer.

### The base algorithm

An outer loop scans the odd numbers from 3 for the next clear bit, then clears that factor's odd multiples. It stops at the square root of the sieve size. Every composite gets its own single-bit OR. Every odd factor takes the same path, including 9, 15 and the other composites, so nothing is assumed beyond 2 being the only even prime.

- **Factors below 128 (dense).** The odd multiples of `p` repeat every `p` 64-bit words. For each factor the sieve builds the pattern of four periods (`4p` words, 256 multiples) in a scratch buffer it owns, with one single-bit OR per multiple. OCaml has no const generics, so the pattern is built at run time, once per factor per pass. Clearing then ORs the pattern into the sieve from the period that holds `p²`. The smaller multiples in that period are composite too; only `p` itself is restored afterwards.
- **Two runs per step.** The dense loop takes two consecutive runs of the pattern at once: each step loads four pattern words and ORs each into the same word of both runs, eight sieve words in all. One pattern load then serves two sieve words. This gained 7.3% at one thread on AMD Zen 5, 8.5% on Zen 3 and 23% on Arm Neoverse N2. An odd run left over takes a one-run loop.
- **Factors of 128 and above (sparse).** Eight multiples repeat every `p` bytes, each at a fixed bit. Their byte offsets and masks are computed once per factor, and a loop walks the `p`-byte chunks with one byte OR per composite. The partial last chunk stops at the first offset past the end.

The inner loops use only `int` arithmetic and the unboxed 64-bit primitives. The generated assembly (`ocamlopt -S`) shows no heap allocation and no boxed `Int64` in them; the only calls are the OCaml 5 safepoint polls on loop back edges. The build uses `-unsafe`, so `Bytes` accesses carry no bounds checks.

Three changes were tried and dropped: a dense limit of 64 or 96 instead of 128 (at most +1.9% on Zen 5, −3.1% to +0.4% on Zen 3), and the sieve in an `Int64` Bigarray (about 8% slower at one thread).

### Faithfulness

All of a sieve's state lives in the `sieve` record: the bit buffer and the pattern scratch. Every pass creates a new record, which allocates both buffers at run time, sized from the sieve size. Nothing is carried from one pass to the next, and no external code does any sieving.

### Parallelism

The multi-threaded runs start one domain per thread with `Domain.spawn`, each running its own sieves until the 5 seconds are up; the passes are summed. The program reports one domain, then all hardware threads (`Domain.recommended_domain_count`), then exactly four when the machine has more than four.

Each pass allocates a 62.5KB sieve and drops it, while almost nothing stays live. With OCaml's default settings the major GC then finishes a cycle every few passes, and each cycle stops every domain. For the multi-domain runs only, the program raises the GC's space overhead from 80 to 1,000, which makes cycles rare. The one-domain run keeps the default. Setting 1,000 from the start of the program cost 3% at one thread on Zen 5, within noise, and gained 16% at all 16 threads.

## Results

(filled from the final scoreboard)

## How this was built

This solution came out of the same experiment in agentic engineering with Claude (Anthropic) as the author's ISPC entries. A Claude Code session ported the design, wrote the self-test and ran the benchmarks; the author set the brief and made the calls.

## Run instructions

### Docker

The `Dockerfile` builds with the official `ocaml/opam:debian-12-ocaml-5.2-flambda` image and runs the binary on `debian:12-slim`:

```
docker build -t primes-ocaml-base .
docker run --rm primes-ocaml-base
```

### Native

With OCaml 5.2 built with flambda (for example the opam switch `ocaml-variants.5.2.0+options` with `ocaml-option-flambda`):

```
sh build.sh
./primes
```

`build.sh` runs `ocamlopt -O3 -unsafe -inline 200 -I +unix unix.cmxa primes.ml -o primes`. Without flambda, `-O3` has no effect.

`PRIMES_TEST=1 ./primes` checks the prime count for every power of ten from 10 to 10⁸ and some edge cases, prints the results and exits non-zero on any mismatch. A separate test against a plain sieve for every size from 1 to 20,000, and every 997th up to 2,000,000, passed.

## Output

One line per run, in the contest's format:

```
cauldnz-ocaml-base;<passes>;<seconds>;<threads>;algorithm=base,faithful=yes,bits=1
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
