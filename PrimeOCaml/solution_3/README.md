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

One bit per odd number: bit `i` stands for `2i + 1`, and a set bit means composite. The sieve is a `Bytes` buffer, read and written as 256-bit vectors, 64-bit or 32-bit little-endian words or single bytes, through compiler primitives that skip bounds checks.

The buffer is not zeroed. `create` writes word 0, so the scan can read the bit for 3. The scan always finds 3 first, and the pass for 3 stores every word without reading it. That pass initialises the rest of the buffer.

### The base algorithm

An outer loop scans the odd numbers from 3 for the next clear bit, then marks that factor's odd multiples as composite. It stops at the square root of the sieve size. Each composite is marked by its own single-bit OR: directly for the large factors, and while the pattern is built for the small ones. Every odd factor takes the same path, including 9, 15 and the other composites, so nothing is assumed beyond 2 being the only even prime.

- **Factors below 128 (dense).** The odd multiples of `p` repeat every `p` 64-bit words. For each factor the sieve builds the pattern of four periods (`4p` words, 256 multiples) in a scratch buffer it owns, with one single-bit OR per multiple. OCaml can't work the pattern out at compile time, so the program builds it at run time, once per factor per pass. Marking then ORs the pattern into the sieve from the period that holds `p²`. The smaller multiples in that period are composite too; the program then clears the bit for `p` itself, which is prime.
- **Factors of 128 and above (sparse).** Eight multiples repeat every `p` bytes, each at a fixed bit. The program works out their byte offsets once per factor, and a loop walks the `p`-byte chunks with one OR per composite. The partial last chunk uses byte ORs, so nothing past the end of the sieve is touched.

### Two kernels: x86-64 and the rest

`primes.ml` holds the outer loop, the factor-3 set-up and the scan. The dense and sparse loops live in two small modules, `Dense` and `Sparse`, and `build.sh` picks their folder from `uname -m`:

| | `amd64/` (x86-64) | `scalar/` (everything else) |
|---|---|---|
| Pattern build | zeroed with 256-bit stores; single-bit ORs into 64-bit words on untagged offsets | `Bytes.fill`; single-bit ORs into 32-bit words on tagged offsets |
| Dense copy | one 256-bit load, OR and store per 32 bytes; two runs of the pattern per loop step, so one pattern load serves two sieve vectors | eight 32-bit words per step, one run at a time |
| Sparse | one OR into the unaligned 64-bit word that starts at the composite's byte, mask in the low byte; offsets untagged; masks are constants | one byte OR per composite; offsets and masks in registers |

The split exists because the two kinds of machine wanted different code. OxCaml's vector types are x86-64 only. The 64-bit-word sparse OR, which won on AMD Zen 3 and Zen 5 (see the table below), lost 28% on Arm Neoverse N2 (Azure Cobalt 100). Two runs per step in the scalar dense copy made no difference on Cobalt (−0.4%), so it stayed out, although the same change gained 23% on Cobalt in the plain OCaml entry; the reason for the difference wasn't investigated.

The scalar dense copy and pattern build use 32-bit stores because of Arm. There OCaml 5 puts a `dmb ishld` barrier before every 64-bit integer store, as part of its memory model; 32-bit stores do not get one. On Cobalt 100 a 62.5KB copy took about 19µs with every 64-bit store form tried and 6.2µs with pairs of 32-bit stores. The change gained 61% at one thread on Cobalt. The 32-bit words are the low and high halves of the 64-bit words used elsewhere, so on a little-endian machine the bit layout is the same. The partial last run of the pattern, in `primes.ml`, still uses 64-bit stores.

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

OxCaml turns on the instruction sets of the machine that built the compiler, so the x86-64 binary uses AVX2 when the OxCaml switch was built on an AVX2 machine. Intel has shipped AVX2 since Haswell (2013) and AMD since Excavator (2015); the binary will not run on an x86-64 CPU without it. Building the compiler inside the Dockerfile, on the machine that will run the program, gives a binary that machine can run. OxCaml 5.2.0+ox cannot emit 512-bit code: a 512-bit load crashes its emitter.

### How it got here

Each change below was kept only if it won when run side by side with the version before, on the same machine, at one or four threads on both AMD Zen 5 and Zen 3, and lost nothing on Intel or on Arm Neoverse N2. A change that only the Arm build compiles was decided on Arm alone. Gains are at one thread, against the version before.

| Change | Zen 5 | Zen 3 | Cobalt 100 |
|---|---|---|---|
| The plain OCaml 5.2 source, compiled by OxCaml | −4.1% | +8.4% | +163% (cause not investigated) |
| 256-bit vector dense copy | +60.5% | +41.4% | +0.1% |
| x86-64 kernels: untagged `int64#` offsets, 64-bit-word sparse OR | +26.6% | +17.4% | +0.0% |
| Constant masks in the x86-64 sparse loop | +5.8% | +12.6% | same binary |
| Two runs per step in the x86-64 dense copy | +7.7% | +4.2% | same binary |
| Pattern build with 256-bit zeroing and untagged ORs | +3.3% | +7.4% | +0.0% |
| 32-bit stores in the scalar dense copy and pattern build | same binary | same binary | +61.4% |

The first row is against the plain OCaml entry of the time, built with the upstream compiler. The last row changed only Arm code, so Cobalt alone decided it. The final figures are in Results.

### Faithfulness

All of a sieve's state lives in the `sieve` record: the bit buffer and the pattern scratch. Every pass creates a new record, which allocates both buffers at run time, sized from the sieve size. Nothing is carried from one pass to the next, and no external code does any sieving.

### Parallelism

The multi-threaded runs start one domain per thread with `Domain.spawn`, each running its own sieves until the five seconds are up; the passes are summed. The program reports one domain, then all hardware threads (`Domain.recommended_domain_count`), then exactly four when the machine has more than four.

Each pass allocates a 62.5KB sieve and drops it, while almost nothing stays live. With OCaml's default settings the major GC then finishes a cycle every few passes, and each cycle stops every domain. For the multi-domain runs the program raises the GC's space overhead from 80 to 1,000, which makes cycles rare. The one-domain run keeps the default. On the plain OCaml entry, setting 1,000 from the start changed the one-thread result on Zen 5 by −3.0% (95% interval ±3.9%), within the noise, and gained 16% with all 16 threads on Zen 5.

## Results

Passes in five seconds, the median of six rounds, with all five entries run in the same rounds on Azure on 2026-10-12. Zen 5 is an AMD EPYC 9V45 (D16as_v7), Zen 3 an AMD EPYC 7763 (D16a_v4) and Cobalt 100 an Arm Neoverse N2 (D4ps_v6). Cobalt has four vCPUs, so its 4T column is all threads. gkpotter's entry runs one thread only.

| | Zen 5 1T | Zen 5 4T | Zen 3 1T | Zen 3 4T | Cobalt 1T | Cobalt 4T |
|---|---|---|---|---|---|---|
| OxCaml (this entry) | 72.2k | 261.5k | 37.2k | 137.0k | 11.8k | 41.9k |
| plain OCaml ([PrimeOCaml/solution_4](../solution_4)) | 32.9k | 121.0k | 18.2k | 69.0k | 3.4k | 13.1k |
| gkpotter, faithful ([PrimeOCaml/solution_1](../solution_1)) | 1.6k | - | 0.8k | - | 0.6k | - |
| mike-barber ([PrimeRust/solution_1](../../PrimeRust/solution_1)) | 126.3k | 471.8k | 56.5k | 220.0k | 42.9k | 171.3k |
| the author's ISPC base ([PrimeISPC/solution_2](../../PrimeISPC/solution_2)) | 138.9k | 518.0k | 60.0k | 233.4k | 42.1k | 168.0k |

The Zen runs measured the version before the last change. That change touched only the Arm files, and the x86-64 binary is the same; Cobalt measured this version. At one thread OxCaml does 2.2 times the passes of plain OCaml on Zen 5 and 3.5 times on Cobalt. It reaches 52% of the ISPC base on Zen 5 and 28% on Cobalt.

## How this was built

This solution came out of the same experiment in agentic engineering with Claude (Anthropic) as the author's ISPC entries. A Claude Code session ported the design, wrote the self-test and ran the benchmarks; the author set the brief and made the decisions.

## Run instructions

### Docker

The `Dockerfile` builds `FROM oxcaml:5.2.0-ox`: Ubuntu 24.04 with the OxCaml switch `5.2.0+ox` on `PATH`. No public registry hosts that image; the author's benchmark machines build it once and cache it locally. `Dockerfile.standalone` builds the same switch from the OxCaml opam repository first, then the solution. Building both took 458 seconds on a 16-vCPU AMD Zen 5 machine:

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
