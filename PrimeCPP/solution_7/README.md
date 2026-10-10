# C++ wheel solution by cauldnz

![Algorithm](https://img.shields.io/badge/Algorithm-wheel-yellowgreen)
![Faithfulness](https://img.shields.io/badge/Faithful-yes-green)
![Parallelism](https://img.shields.io/badge/Parallel-yes-green)
![Bit count](https://img.shields.io/badge/Bits-1-green)

A sieve of Eratosthenes on a mod-30 wheel, in plain C++20, built with the distribution's GCC
at `-O3 -march=native`. It uses no intrinsics and no inline assembly. The one extension is
GCC's `vector_size` attribute (Clang has it too), which names a block of 16 words as one value;
the compiler splits it into the vector registers the target has.

It is a port of the design of the author's ISPC wheel entry
([PrimeISPC/solution_1](../../PrimeISPC/solution_1)), written as C++ rather than translated
line by line. [solution_6](../solution_6) is its base-algorithm companion.

## Implementation

### Storage

Only numbers coprime to 30 are stored, in eight bit-planes, one per residue `R` in {1, 7, 11,
13, 17, 19, 23, 29}. Bit `m` of plane `R` stands for `30m + R`, and a set bit means composite.
Up to 1,000,000 the planes take 8 × 521 64-bit words, about 33KB, allocated with
`posix_memalign` once per pass.

### Each plane is a stride sieve

The multiples of a prime `p` that fall in one plane step through it with stride `p`, so each
plane is a small, regular sieve of its own. A modular inverse mod 30 gives the first multiple
in each plane.

### Small primes stream repeating patterns

A stride-`p` bit pattern repeats every `p` 64-bit words. Because 64 is invertible modulo any
odd `p`, every bit offset of the pattern is a whole-word rotation of one base pattern. Each
prime below 256 builds one base pattern, shared by all eight planes, and a 64-entry table of
starting rotations, filled while the pattern is built. The patterns are then ORed into the
sieve 16 words at a time, with contiguous loads and no divisions in the loop.

Several primes are fused into one pass over a plane, so each sieve word is loaded and stored
once per group: six primes when the target has AVX-512, eight otherwise. Every member of a
group starts at the first word any member touches, so no member needs a lead-in of its own.
Members then also mark their multiples below `p²`, which are composite, and `p` itself, which
is cleared again afterwards. The last block of a plane runs on into padding at the end of the
plane instead of being masked. The fused loop is a template over the number of members, picked
by a fold over `std::integer_sequence`, so each member's phase and period are fixed-size locals
that GCC keeps in registers.

### Wheel tile

Multiples of 7 and 11 repeat every 77 words in every plane. The program marks that period
once and copies it along each plane. Then 13 runs on its own, after which every bit below 17²
is final.

### Large primes

Primes of 256 and above set at most one bit per word. They use scalar strided bit-setting, with
four planes advanced in one loop, so four independent memory streams are in flight, and then
the other four. The ISPC entry runs all eight planes in one loop; in C++, GCC spilled the eight
indices to the stack, and that phase took 40% more cycles than with four.

### Faithfulness

All of a sieve's state, including its pattern scratch space, lives in the `Sieve` class.
Every pass constructs a new instance, which allocates its buffers at run time, sized from the
sieve size. Nothing is precomputed or carried from one pass to the next, and no external
dependency does any sieving.

### Parallelism

The multi-threaded runs start one `std::thread` per thread, each running its own sieves. The
thread count comes from the process's CPU affinity mask, so a container limited with
`--cpuset-cpus` runs the right number. The program reports one thread, then all, half and a
quarter of the available CPUs, because SMT siblings share an L1 cache and fewer threads can
finish more passes.

## Run instructions

### Docker

```
docker build -t primes-cpp-wheel .
docker run --rm primes-cpp-wheel
```

### Native (Linux, GCC 10 or later)

```
g++ -std=c++20 -O3 -march=native -pthread primes.cpp -o primes
./primes
```

`PRIMES_TEST=1 ./primes` checks the prime count for every power of ten from 10 to 10⁸, prints
one line per size ending in 1 (pass) or 0 (fail), and exits non-zero on any mismatch.
`PRIMES_TEST=2 ./primes` prints the count for every size from 1 to 5,000 and every 997th size
from there to 400,000, to compare against a reference sieve.

## Output

Intel Xeon at 2.1GHz with AVX-512, 4 vCPUs, Ubuntu 24.04, GCC 13.3, native build:

```
cauldnz-cpp-wheel;100071;5.000059;1;algorithm=wheel,faithful=yes,bits=1
cauldnz-cpp-wheel;426821;5.000169;4;algorithm=wheel,faithful=yes,bits=1
cauldnz-cpp-wheel;208063;5.000175;2;algorithm=wheel,faithful=yes,bits=1
```
