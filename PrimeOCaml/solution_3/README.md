# OxCaml solution by cauldnz

![Algorithm](https://img.shields.io/badge/Algorithm-base-green)
![Faithfulness](https://img.shields.io/badge/Faithful-yes-green)
![Parallelism](https://img.shields.io/badge/Parallel-yes-green)
![Bit count](https://img.shields.io/badge/Bits-1-green)

A sieve of Eratosthenes that follows the base algorithm, built with [OxCaml](https://oxcaml.org), Jane Street's branch of the OCaml compiler with the flambda2 optimiser. It starts from the plain OCaml 5.2 entry in [PrimeOCaml/solution_4](../solution_4) and adds OxCaml's vector types and untagged integers in the hot loops on x86-64. It uses only the standard library and `unix` (for the clock).

The design is that of the author's ISPC base entry ([PrimeISPC/solution_2](../../PrimeISPC/solution_2)) and its Rust port ([PrimeRust/solution_9](../../PrimeRust/solution_9)). That design follows mike-barber's Rust entry ([PrimeRust/solution_1](../../PrimeRust/solution_1)) and GordonBGood's Chapel entry ([PrimeChapel/solution_1](../../PrimeChapel/solution_1)).

The output label is `cauldnz-oxcaml-base`, with the tags `algorithm=base,faithful=yes,bits=1`.

## Implementation

### Storage

One bit per odd number: bit `i` stands for `2i + 1`, and a set bit means composite. The sieve is a `Bytes` buffer, read and written as 64-bit little-endian words, 256-bit vectors or single bytes through compiler primitives that skip bounds checks.

The buffer is not zeroed. `create` writes word 0, so the scan can read the bit for 3. The scan always finds 3 first, and the pass for 3 stores every word without reading it. That pass initialises the rest of the buffer.

### The base algorithm

An outer loop scans the odd numbers from 3 for the next clear bit, then clears that factor's odd multiples. It stops at the square root of the sieve size. Every composite gets its own single-bit OR. Every odd factor takes the same path, including 9, 15 and the other composites, so nothing is assumed beyond 2 being the only even prime.

- **Factors below 128 (dense).** The odd multiples of `p` repeat every `p` 64-bit words. For each factor the sieve builds the pattern of four periods (`4p` words, 256 multiples) in a scratch buffer it owns, with one single-bit OR per multiple. OCaml has no const generics, so the pattern is built at run time, once per factor per pass. Clearing then ORs the pattern into the sieve from the period that holds `p²`. The smaller multiples in that period are composite too; only `p` itself is restored afterwards.
- **Factors of 128 and above (sparse).** Eight multiples repeat every `p` bytes, each at a fixed bit. Their byte offsets are computed once per factor, and a loop walks the `p`-byte chunks with one OR per composite. The partial last chunk uses byte ORs, so nothing past the end of the sieve is touched.

### Two kernels: x86-64 and the rest

`primes.ml` holds the outer loop, the factor-3 set-up and the scan. The dense and sparse loops live in two small modules, `Dense` and `Sparse`, and `build.sh` picks their folder from `uname -m`:

| | `amd64/` (x86-64) | `scalar/` (everything else) |
|---|---|---|
| Pattern build | zeroed with 256-bit stores; single-bit ORs on untagged offsets | `Bytes.fill`; single-bit ORs on tagged offsets |
| Dense copy | one 256-bit load, OR and store per 32 bytes; two runs of the pattern per loop step, so one pattern load serves two sieve vectors | four 64-bit words per step, one run at a time |
| Sparse | one OR into the unaligned 64-bit word that starts at the composite's byte, mask in the low byte; offsets untagged; masks are constants | one byte OR per composite; offsets and masks in registers |

The split exists because the two kinds of machine wanted different code. OxCaml's vector types are x86-64 only. And the 64-bit-word sparse OR, which won 21% to 33% on AMD Zen 3 and Zen 5, lost 28% on Arm Neoverse N2 (Azure Cobalt 100). Two runs per step in the scalar dense copy made no difference on Cobalt (−0.4%), so it stayed out.

In the x86-64 sparse loop each of the eight composites in a chunk sits at a different bit, so the loop takes them in bit order and each mask is the constant `1 lsl k`. Only the eight offsets stay live, not eight offsets and eight masks, so the loop fits in registers: about 4.9 instructions per composite in the `-S` listing, loop overhead and safepoint poll included. The word ORed at offset `o` stays inside its chunk, since `o + 8 <= p` for `p` of 128 and above.

The inner loops do not allocate. The `-S` listings show no heap allocation and no boxed `Int64` in them; the only calls are the OCaml 5 safepoint polls on loop back edges.

### OxCaml features used

All of these are in `amd64/`; `scalar/` and `primes.ml` are plain OCaml that OxCaml also compiles.

- **256-bit vectors**: the type `int64x4`, the builtins `caml_avx_vec256_or` and `caml_avx_vec256_xor` (declared as `[@@builtin]` externals, emitted inline as `vpor`/`vpxor`) and the unaligned `Bytes` primitives `%caml_bytes_getu256u` and `%caml_bytes_setu256u`. Used in the dense copy and the pattern zeroing.
- **Untagged 64-bit integers**: `int64#` byte offsets and words, `#0L` literals and the primitives indexed by them (`%caml_bytes_getu256u_indexed_by_int64#`, `%caml_bytes_get64u#_indexed_by_int64#` and their `set` forms). With a tagged `int` offset every access first shifts the tag off. OxCaml has no byte access indexed by an untagged integer, which is why the x86-64 sparse loop ORs a 64-bit word.
- **`let mutable`** for the loop counters that hold `int64#` values, which a `ref` cannot hold.

`ocamlopt` emits the builtins inline but still lists their C names among the program's symbols, so `amd64/simd_stubs.c` defines both as functions that abort. They are never called and do no sieving.

Not used: `local_` allocation, since the loops allocate nothing, and `Domain.Safe.spawn`. The multi-domain runs use the ordinary `Domain.spawn` with OxCaml's two alerts about it switched off in `build.sh`.

### AVX2 on x86-64

OxCaml turns on the instruction sets of the machine that built the compiler, so the x86-64 binary uses AVX2 when the OxCaml switch was built on an AVX2 machine. Intel has shipped AVX2 since Haswell (2013) and AMD since Excavator (2015); the binary will not run on an x86-64 CPU without it. OxCaml 5.2.0+ox cannot emit 512-bit code: a 512-bit load crashes its emitter.

### How it got here

Each change below was kept under a paired-run rule at one and four threads on AMD Zen 5 and Zen 3, with Intel and Arm Neoverse N2 as gates. Gains are at one thread, against the version before.

| Change | Zen 5 | Zen 3 |
|---|---|---|
| The plain OCaml 5.2 source, compiled by OxCaml | −4.1% | +8.4% |
| 256-bit vector dense copy | +60.5% | +41.4% |
| x86-64 kernels: untagged `int64#` offsets, 64-bit-word sparse OR | +26.6% | +17.4% |
| Constant masks in the x86-64 sparse loop | +5.8% | +12.6% |
| Two runs per step in the x86-64 dense copy | +7.7% | +4.2% |
| Pattern build with 256-bit zeroing and untagged ORs | +3.3% | +7.4% |

The first row is against the plain OCaml entry built with the upstream compiler. Arm was unchanged by every x86-64 change. The final figures are in Results.

### Faithfulness

All of a sieve's state lives in the `sieve` record: the bit buffer and the pattern scratch. Every pass creates a new record, which allocates both buffers at run time, sized from the sieve size. Nothing is carried from one pass to the next, and no external code does any sieving.

### Parallelism

The multi-threaded runs start one domain per thread with `Domain.spawn`, each running its own sieves until the 5 seconds are up; the passes are summed. The program reports one domain, then all hardware threads (`Domain.recommended_domain_count`), then exactly four when the machine has more than four.

Each pass allocates a 62.5KB sieve and drops it, while almost nothing stays live. With OCaml's default settings the major GC then finishes a cycle every few passes, and each cycle stops every domain. For the multi-domain runs the program raises the GC's space overhead from 80 to 1,000, which makes cycles rare. The one-domain run keeps the default, which was about 10% faster there.

## Results

(filled from the final scoreboard)

## How this was built

This solution came out of the same experiment in agentic engineering with Claude (Anthropic) as the author's ISPC entries. A Claude Code session ported the design, wrote the self-test and ran the benchmarks; the author set the brief and made the calls.

## Run instructions

### Docker

The `Dockerfile` builds `FROM oxcaml:5.2.0-ox`: Ubuntu 24.04 with the OxCaml switch `5.2.0+ox` on `PATH`. No public registry hosts that image; the author's benchmark machines build it once and cache it locally. `Dockerfile.standalone` builds the same switch from the OxCaml opam repository first, then the solution. That took 458 seconds on a 16-vCPU AMD Zen 5 machine, and longer on fewer cores:

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

`build.sh` picks `amd64/` or `scalar/` and runs `ocamlopt -O3 -unsafe -I +unix -I <dir> unix.cmxa [amd64/simd_stubs.c] <dir>/dense.ml <dir>/sparse.ml primes.ml -o primes`, plus two `-alert` flags that silence OxCaml's warnings about `Domain.spawn`. OxCaml prefers its own threading library; this program spawns no more domains than `Domain.recommended_domain_count`.

`PRIMES_TEST=1 ./primes` checks the prime count for every power of ten from 10 to 10⁸ and some edge cases, prints the results and exits non-zero on any mismatch. A separate test against a plain sieve for every size from 1 to 20,000, and every 997th up to 2,000,000, passed.

## Output

One line per run, in the contest's format:

```
cauldnz-oxcaml-base;<passes>;<seconds>;<threads>;algorithm=base,faithful=yes,bits=1
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
