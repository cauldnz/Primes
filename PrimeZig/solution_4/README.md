# Zig solution by cauldnz

![Algorithm](https://img.shields.io/badge/Algorithm-base-green)
![Algorithm](https://img.shields.io/badge/Algorithm-wheel-yellowgreen)
![Faithfulness](https://img.shields.io/badge/Faithful-yes-green)
![Parallelism](https://img.shields.io/badge/Parallel-no-green)
![Parallelism](https://img.shields.io/badge/Parallel-yes-green)
![Bit count](https://img.shields.io/badge/Bits-1-green)

Two sieves of Eratosthenes in one Zig program, with no dependencies beyond Zig's standard library:

- `cauldnz-zig-base` follows the base algorithm, one bit per odd number.
- `cauldnz-zig-wheel` stores only numbers coprime to 30, one bit each, in eight bit-planes.

Each runs for 5 seconds on one thread, then on all, half and a quarter of the hardware threads. The designs come from the author's ISPC entries, [PrimeISPC/solution_2](../../PrimeISPC/solution_2) (base) and [PrimeISPC/solution_1](../../PrimeISPC/solution_1) (wheel). Zig's `comptime` replaces the macros and code generators those designs would otherwise need.

## Implementation

### Base algorithm

Bit `i` stands for the odd number `2i + 1`, and a set bit means composite. An outer loop scans odd numbers from 3 for the next clear bit, clears that factor's odd multiples and stops at the square root of the sieve size. In the source, every composite is cleared by its own single-bit OR. The clearing routines follow mike-barber's Rust entry ([PrimeRust/solution_1](../../PrimeRust/solution_1)):

- Factors below 128. The odd multiples of `p` repeat every `p` 64-bit words, 64 to a period, at fixed word and bit offsets. A `switch` with an `inline` prong instantiates `denseReset` for every odd factor from 3 to 127, so each offset and mask is a compile-time constant. The routine loads a vector of words, ORs in each composite that falls in it as its own single-bit constant, then stores it; LLVM folds the constants. Every odd factor has a resetter, 9 and 15 included, so the program assumes nothing about which numbers are prime beyond 2 being the only even one. Clearing starts at the period that holds `p²`. The smaller multiples in that period are composite too, and `p` itself is restored afterwards.
- Factors of 128 and above. The same idea over bytes: eight multiples repeat every `p` bytes. Their byte offsets are computed once per factor, and their single-bit masks depend only on `p mod 16`, so a second `inline` switch makes them constants. A pointer walks the sieve `p` bytes at a time.

### Wheel algorithm

Bit `m` of plane `R` stands for `30m + R`, for the eight residues `R` coprime to 30. Within one plane, the multiples of a prime `p` form a plain stride-`p` progression, so their word pattern repeats every `p` words. The sieve runs in two phases:

1. Multiples of 7 and 11 repeat every 77 words in every plane. For each plane the program marks one 77-word tile in scratch space, then writes the plane in one pass: each word is a tile word ORed with the matching word of 13's pattern. After that, every bit below 17² is final, so the program can read candidates from the sieve itself. Folding 13 into the copy saves a separate read-modify-write pass over the planes.
2. Primes below 256 are applied in groups of eight. The program builds each prime's pattern once, then makes one pass over each plane, loading each vector of sieve words once and ORing in all eight patterns. Larger primes set single bits, with all eight planes advancing in one loop.

The fused loop works in 16 words at a time on SSE2 and NEON and 32 with AVX2 or AVX-512. Each step updates one scalar phase per pattern, and wider steps spread that cost: on the Xeon below, an SSE2 build ran 18% faster with eight words per step than with four, and 16 did no worse than eight.

### Faithfulness

All of a sieve's state lives in a struct, `BaseSieve` or `WheelSieve`; Zig has no classes, and a struct with methods is the nearest equivalent. For the wheel this includes the pattern scratch space. Every pass creates a new instance, which allocates its buffers at run time, sized from the sieve size, and frees them at the end. Nothing is precomputed or carried from one pass to the next.

Each thread allocates from its own `std.heap.ArenaAllocator` over page memory and resets it after each pass, so the next pass gets the same pages back, as a thread-caching `malloc` would hand them out. Every sieve writes all of its memory before it reads any. The arena replaced musl's `malloc`, which the Alpine image would otherwise use. With `malloc`, the container ran the base entry at 33,000 passes on one thread against 40,000 with the arena, and the wheel entry finished fewer passes on four threads than on one.

### Parallelism

Each thread runs its own sieves. Results are reported for one thread, then all, half and a quarter of the hardware threads, because SMT siblings share an L1 cache and fewer threads can finish more passes.

### Target CPU

The build targets the CPU it runs on (`-mcpu=native`). The drag race builds each image on the
machine that benchmarks it, and the C++ and Rust base entries build the same way
(`-march=native`, `target-cpu=native`). On the Xeon below, an AVX2 build ran the wheel 43%
faster than a baseline SSE2 build at one thread, about 102,000 passes against 71,000; the base
entry gained nothing. `ZIG_CPU`, set for `build.sh` or as a Docker build argument, overrides
the target, for example `ZIG_CPU=baseline` for a portable binary.

## How this was built

This solution came out of the same experiment in agentic engineering with Claude (Anthropic) as the author's ISPC entries. A Claude Code session ported the designs, wrote the self-tests and ran the benchmarks; the author set the brief and made the calls. Each change was self-tested with `PRIMES_TEST=1` and timed in interleaved runs against the previous build.

## Run instructions

### Docker

```
docker build -t primes-zig-4 .
docker run --rm primes-zig-4
```

### Native

Install Zig 0.13.0, the version Alpine 3.21 packages, then:

```
sh build.sh
./primes
```

`PRIMES_TEST=1 ./primes` checks the prime count for every power of ten from 10 to 10⁸ and for 1, 2, 3, 127 and 16,383, for both algorithms. It writes the results to stderr and exits non-zero on any mismatch.

## Output

Intel Xeon at 2.1GHz, 4 vCPUs on a shared cloud instance, Docker image as built above:

```
cauldnz-zig-base;39831;5.000111;1;algorithm=base,faithful=yes,bits=1
cauldnz-zig-base;156904;5.001120;4;algorithm=base,faithful=yes,bits=1
cauldnz-zig-base;82111;5.000284;2;algorithm=base,faithful=yes,bits=1
cauldnz-zig-wheel;75476;5.000108;1;algorithm=wheel,faithful=yes,bits=1
cauldnz-zig-wheel;206875;5.000745;4;algorithm=wheel,faithful=yes,bits=1
cauldnz-zig-wheel;153465;5.000343;2;algorithm=wheel,faithful=yes,bits=1
```
