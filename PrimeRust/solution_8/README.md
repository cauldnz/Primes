# Rust solution by cauldnz

![Algorithm](https://img.shields.io/badge/Algorithm-wheel-yellowgreen)
![Faithfulness](https://img.shields.io/badge/Faithful-yes-green)
![Parallelism](https://img.shields.io/badge/Parallel-yes-green)
![Bit count](https://img.shields.io/badge/Bits-1-green)

A sieve of Eratosthenes on a mod-30 wheel, in stable Rust with no dependencies beyond the standard library. It is the design of the author's ISPC entry ([PrimeISPC/solution_1](../../PrimeISPC/solution_1)) written as ordinary Rust: the SIMD comes from LLVM vectorising plain loops over fixed-size arrays, built with `-C target-cpu=native`.

## Implementation

### Storage

Only numbers coprime to 30 are stored, in eight bit-planes, one per residue `R` in {1, 7, 11, 13, 17, 19, 23, 29}. Bit `m` of plane `R` stands for `30m + R`, and a set bit means composite. Up to 1,000,000 the planes take 8 × 521 64-bit words, about 33KB. Within one plane the multiples of a prime `p` step through the bits with stride `p`, so each plane is a small stride sieve of its own. A modular inverse mod 30 gives the first multiple in each plane.

### Small primes stream repeating patterns

A stride-`p` bit pattern repeats every `p` 64-bit words. Because 64 is invertible modulo any odd `p`, every bit offset of the pattern is a whole-word rotation of one base pattern. Each prime builds that pattern once, with a 64-entry table of starting phases, and it serves all eight planes.

Up to eight primes below 256 are fused into one pass over a plane. `apply_group::<N>` takes the member count as a const generic, so the per-member loop unrolls and each member's phase stays in a register. Each step loads 32 sieve words into a `[u64; 32]`, ORs in a 32-word slice of every member's pattern and stores the words back: one load and one store per sieve word for the whole group. A step of 32 words was 5% faster than 16 on an AVX-512 Xeon. Every member starts at the first word any member touches, so none needs a lead-in. A member then also marks its multiples below `p²`, which are composite, and `p` itself, which is cleared afterwards. The last partial step runs on into padding at the end of each plane instead of taking a scalar tail.

### Wheel tile

Multiples of 7 and 11 repeat every 77 words in every plane. Each pass marks one 77-word period in a small array and copies it along each plane as it fills the plane's memory, so every word is written once before anything reads it. Then 13 runs on its own, after which every bit below 17² is final.

### Large primes

Primes from 256 to 1,000 set at most one bit per word. All eight planes advance in one loop, giving eight independent read-modify-write streams. This is the hottest loop, and the one place the code uses `unsafe`: the number of rounds is computed so that every stream stays inside its plane, and dropping the bounds checks made the whole run 13% faster at one thread. The tails after the last full round use checked indexing.

### Faithfulness

All of a sieve's state is in the `Sieve` struct, including the pattern rows. Every pass creates a new `Sieve`, which allocates its buffers at run time, sized from the sieve size, and drops them at the end of the pass. Nothing is carried from one pass to the next, and no external code does any sieving.

### Parallelism

The multi-threaded runs start one thread per hardware thread with `std::thread::scope`, each running its own sieves. The thread count comes from `std::thread::available_parallelism`, which on Linux counts the CPUs in the process's affinity mask, so a container limited with `--cpuset-cpus` is not oversubscribed. The program reports results for one thread, then all, half and a quarter of the hardware threads, because SMT siblings share an L1 cache and fewer threads can finish more passes.

## How this was built

This solution came out of the same experiment in agentic engineering with Claude (Anthropic) as the author's ISPC entries. A Claude Code session ported the design, wrote the self-test and ran the benchmarks; the author set the brief and made the calls.

## Run instructions

### Docker

```
docker build -t primes-rust-wheel .
docker run --rm primes-rust-wheel
```

### Native

With Rust 1.84 or later:

```
cargo run --release
```

### Options

- `PRIMES_TEST=1` checks the prime count for every power of ten from 10 to 10⁸, then for 5,396 sizes (every size from 1 to 4,999, then every 997th up to 399,812) against a plain reference sieve. It prints the results and exits non-zero on any mismatch.
- `PRIMES_DENSE_MAX=<n>` sets the size below which primes are applied as word patterns rather than single bits. The default is 256.

## Output

Intel Xeon (AVX-512) at 2.1GHz, 4 vCPUs, a shared cloud VM, native build with Rust 1.97:

```
cauldnz-rust-wheel;122780;5.000014;1;algorithm=wheel,faithful=yes,bits=1
cauldnz-rust-wheel;315642;5.000212;4;algorithm=wheel,faithful=yes,bits=1
cauldnz-rust-wheel;215737;5.000106;2;algorithm=wheel,faithful=yes,bits=1
```

Self-test:

```
size 10 -> 4 primes (expected 4) 1
size 100 -> 25 primes (expected 25) 1
size 1000 -> 168 primes (expected 168) 1
size 10000 -> 1229 primes (expected 1229) 1
size 100000 -> 9592 primes (expected 9592) 1
size 1000000 -> 78498 primes (expected 78498) 1
size 10000000 -> 664579 primes (expected 664579) 1
size 100000000 -> 5761455 primes (expected 5761455) 1
5396 sizes from 1 to 399812 -> 0 wrong 1
```
