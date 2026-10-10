# Rust solution by cauldnz

![Algorithm](https://img.shields.io/badge/Algorithm-base-green)
![Faithfulness](https://img.shields.io/badge/Faithful-yes-green)
![Parallelism](https://img.shields.io/badge/Parallel-yes-green)
![Bit count](https://img.shields.io/badge/Bits-1-green)

A sieve of Eratosthenes that follows the base algorithm, in stable Rust with no dependencies beyond the standard library. It is the design of the author's ISPC base entry ([PrimeISPC/solution_2](../../PrimeISPC/solution_2)) written as ordinary Rust, built with `-C target-cpu=native`. That design follows mike-barber's Rust entry ([PrimeRust/solution_1](../solution_1)) and GordonBGood's Chapel entry ([PrimeChapel/solution_1](../../PrimeChapel/solution_1)).

## Implementation

### Storage

One bit per odd number: bit `i` stands for `2i + 1`, and a set bit means composite. The buffer is allocated with a 64-byte alignment and is not zeroed. `Sieve::new` writes word 0, so the scan can read the bit for 3. The scan always finds 3 first, and the pass for 3 stores every word without reading it, which initialises the rest of the buffer. No word is read before it is written.

### The base algorithm

An outer loop scans for the next clear bit, then clears that factor's odd multiples from its square, stepping `2 × factor` through the numbers. It stops at the square root of the sieve size. Every composite gets its own single-bit OR in the source.

- **Factors below 128.** The odd multiples of `p` repeat every `p` 64-bit words, 64 multiples to a period. `clear_dense::<P, INIT>` is instantiated for every odd factor from 3 to 127, with the factor as a const generic. It works on runs of four periods, `p` vectors of four words each. `Dense::<P>::MASKS` holds one `[u64; 4]` per vector, built at compile time by a const block that sets each of the run's 256 multiples with its own single-bit OR. At run time each vector is one load, one OR and one store. The last, partial run takes the same masks for as many whole vectors as fit, then one to three single words. Every odd factor has a case, including 9, 15 and the other composites, so the resetters assume nothing about which numbers are prime beyond 2 being the only even one. The set-up above is the one place the program relies on 3 being the first prime.
- **Factors of 128 and above.** The same idea over bytes: eight multiples repeat every `p` bytes, each at a fixed bit position. Their byte offsets are computed once per factor. A pointer walks over the `p`-byte chunks, so each composite is one OR instruction on memory. The eight single-bit masks depend only on `p mod 16`, so a `match` picks them as const generics.

The resetters work on raw pointers, without bounds checks. Each has a `# Safety` note giving the bounds it relies on, and `cargo test` checks every sieve size from 1 to 20,000, and every 997th up to 2,000,000, against a plain sieve, with debug assertions on.

LLVM's SLP vectoriser gives mike-barber's dense resetters vector ORs for some factors and leaves others as one OR per word. Writing the vectors as `[u64; 4]` arrays makes every dense factor take vector ORs.

### Faithfulness

All of a sieve's state lives in the `Sieve` struct. Every pass creates a new `Sieve`, which allocates its buffer at run time, sized from the sieve size, and frees it when dropped at the end of the pass. Nothing is carried from one pass to the next, and no external code does any sieving.

### Parallelism

The multi-threaded runs start one thread per hardware thread with `std::thread::scope`, each running its own sieves. The thread count comes from `std::thread::available_parallelism`, which on Linux counts the CPUs in the process's affinity mask, so a container limited with `--cpuset-cpus` is not oversubscribed. The program reports results for one thread, then all, half and a quarter of the hardware threads, because SMT siblings share an L1 cache and fewer threads can finish more passes.

## How this was built

This solution came out of the same experiment in agentic engineering with Claude (Anthropic) as the author's ISPC entries. A Claude Code session ported the design, wrote the self-test and ran the benchmarks; the author set the brief and made the calls.

## Run instructions

### Docker

```
docker build -t primes-rust-base .
docker run --rm primes-rust-base
```

### Native

With Rust 1.84 or later:

```
cargo run --release
```

`PRIMES_TEST=1` checks the prime count for every power of ten from 10 to 10⁸ and some edge cases, prints the results and exits non-zero on any mismatch.

## Output

Intel Xeon (AVX-512) at 2.1GHz, 4 vCPUs, a shared cloud VM, native build with Rust 1.97:

```
cauldnz-rust-base;49874;5.000037;1;algorithm=base,faithful=yes,bits=1
cauldnz-rust-base;205055;5.000298;4;algorithm=base,faithful=yes,bits=1
cauldnz-rust-base;103833;5.000163;2;algorithm=base,faithful=yes,bits=1
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
