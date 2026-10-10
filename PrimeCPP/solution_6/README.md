# C++ base solution by cauldnz

![Algorithm](https://img.shields.io/badge/Algorithm-base-green)
![Faithfulness](https://img.shields.io/badge/Faithful-yes-green)
![Parallelism](https://img.shields.io/badge/Parallel-yes-green)
![Bit count](https://img.shields.io/badge/Bits-1-green)

A sieve of Eratosthenes that follows the base algorithm, in plain C++20, built with the
distribution's GCC at `-O3 -march=native`. It uses no intrinsics, no inline assembly and no
libraries beyond the standard library and `sched_getaffinity`.

It is a port of the design of the author's ISPC base entry
([PrimeISPC/solution_2](../../PrimeISPC/solution_2)), written as C++ rather than translated
line by line. [solution_7](../solution_7) is its wheel companion.

## Implementation

### Storage

One bit per odd number: bit `i` stands for `2i + 1`, and a set bit means composite. The
buffer is allocated with `posix_memalign` on a 64-byte boundary, one per pass.

The constructor zeroes word 0 only, so the scan can read the bit for 3. The scan always finds
3 first, and the pass for 3 writes every word of the sieve instead of reading it: it zeroes
each word and sets the multiples of 3 in the same sweep. That saves one pass over the buffer.

### The base algorithm

An outer loop finds the next prime by scanning for the next clear bit, then clears that
prime's odd multiples. It stops at the square root of the sieve size. In the source every
composite is cleared by its own single-bit OR; no operation clears two composites. The
clearing routines follow mike-barber's Rust solution
([PrimeRust/solution_1](../../PrimeRust/solution_1)) and GordonBGood's Chapel solution
([PrimeChapel/solution_1](../../PrimeChapel/solution_1)).

- **Factors below 128.** The odd multiples of `p` repeat with a period of `p` 64-bit words,
  and each period holds exactly 64 multiples at fixed word and bit offsets. `clear_dense<P>`
  is a template instantiated for every odd factor from 3 to 127, through a table of function
  pointers built at compile time with `std::index_sequence`. Within one period a fold
  expression writes the 64 single-bit ORs, each with a constant word offset and mask. GCC
  merges the ORs that land in one word into one constant and vectorises the period's words:
  for `p = 11` the loop is 11 vector loads, ORs and stores per four periods. Every odd factor
  has an instance, including 9, 15 and the other composites, so the clearing code assumes
  nothing about which numbers are prime beyond 2 being the only even one. Clearing starts at
  the period that holds `p²`; the smaller multiples in that period are composite too, and only
  `p` itself is restored afterwards.
- **Factors of 128 and above.** The same idea over bytes: eight multiples repeat every `p`
  bytes, each at a fixed bit position. Their byte offsets are computed once per factor and a
  pointer walks over the `p`-byte chunks, so each composite costs one OR instruction. The
  eight masks depend only on `p mod 16`, so `clear_sparse<E>` is a template over that residue
  and a `switch` picks the instance.

### Faithfulness

All of a sieve's state lives in the `Sieve` class. Every pass constructs a new instance, which
allocates its buffer at run time, sized from the sieve size. Nothing is precomputed or carried
from one pass to the next, and no external dependency does any sieving.

### Parallelism

The multi-threaded runs start one `std::thread` per thread, each running its own sieves. The
thread count comes from the process's CPU affinity mask, so a container limited with
`--cpuset-cpus` runs the right number. The program reports one thread, then all, half and a
quarter of the available CPUs, because SMT siblings share an L1 cache and fewer threads can
finish more passes.

## Run instructions

### Docker

```
docker build -t primes-cpp-base .
docker run --rm primes-cpp-base
```

### Native (Linux, GCC 10 or later)

```
g++ -std=c++20 -O3 -march=native -pthread primes.cpp -o primes
./primes
```

`PRIMES_TEST=1 ./primes` checks the prime count for every power of ten from 10 to 10⁸ and
some edge cases, prints one line per size ending in 1 (pass) or 0 (fail), and exits non-zero
on any mismatch. `PRIMES_TEST=2 ./primes` prints the count for every size from 1 to 5,000 and
every 997th size from there to 400,000, to compare against a reference sieve.

## Output

Intel Xeon at 2.1GHz with AVX-512, 4 vCPUs, Ubuntu 24.04, GCC 13.3, native build:

```
cauldnz-cpp-base;51697;5.000008;1;algorithm=base,faithful=yes,bits=1
cauldnz-cpp-base;199640;5.000140;4;algorithm=base,faithful=yes,bits=1
cauldnz-cpp-base;96486;5.000197;2;algorithm=base,faithful=yes,bits=1
```
