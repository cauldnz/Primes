# Fai solution by cauldnz

![Algorithm](https://img.shields.io/badge/Algorithm-base-green)
![Faithfulness](https://img.shields.io/badge/Faithful-yes-green)
![Parallelism](https://img.shields.io/badge/Parallel-yes-green)
![Bit count](https://img.shields.io/badge/Bits-1-green)

A plain base sieve in [Fai](https://github.com/Krzysztof-Cieslak/fai) 0.1.0, a strict, pure
functional language compiled ahead of time with Cranelift.

- One bit per odd number, 32 bits to each element of an `Array Int`. Fai stores an array
  element as a tagged 63-bit integer and boxes anything larger, so a full 64-bit word with its
  top bits set would allocate on every store. With 64 bits per element the program ran 2.5
  times fewer passes.
- The next factor is found by scanning the odd numbers upward from 3. Every composite gets its
  own single-bit OR, by one of two paths. The design is that of the author's plain OCaml entry
  ([PrimeOCaml/solution_4](../../PrimeOCaml/solution_4)), on 32-bit slots.
  - **Dense factors (below 16 in `primes`, below 32 in `primes-parallel`).** The odd
    multiples of `p` repeat every `p` slots. Each pass
    builds the pattern of four periods (`4p` slots, 128 multiples) in a scratch `Array Int`
    allocated with the sieve, with one read-OR-write per multiple, then ORs the pattern into
    the sieve slot by slot from the period that holds p², and clears the bit of `p` itself when
    the pattern set it. Each step reads a pattern slot once and ORs it into the same slot of
    two consecutive runs.
  - **Sparse factors (the rest).** Each multiple is set with its own read-OR-write, from p² in
    steps of 2p. In `primes` the loop handles four multiples per step (each still its own
    read-OR-write), in `primes-parallel` one.
- A new array (and pattern scratch) every pass. Fai has no mutation in the language: the array is threaded through
  tail-recursive loops and, because it is uniquely owned, `Array.unsafeSet` updates it in place
  (Perceus reference counting). A debugger count of the runtime's copy path shows zero copies
  over the whole self-test.
- Two programs, run one after the other by `run.sh`. Fai 0.1.0 compiles a whole program in
  a "concurrent" mode when the effects of `main` include `Concurrency`, and that mode turns
  off the inline array fast path: every `Array.unsafeGet` and `Array.unsafeSet` becomes a
  call to `fai_array_get_borrowed` or `fai_array_set` (in the compiler,
  `crates/fai-codegen/src/emit.rs`, `array_prim`). Without it, a read-OR-write of a sieve
  slot is about 29 inline instructions and no calls, and the single-threaded run does 2.9
  times the passes. So `primes` (`Primes.fai`) has no `Concurrency` effect: it does the
  single-threaded run and the self-test. `primes-parallel` (`PrimesParallel.fai`, using the
  worker from `Primes.fai` with the threaded kernel) does the multi-threaded runs: one independent sieve
  loop per task with `Async.parallel`, each task counting its own passes until the shared
  deadline. Those runs still pay the calls. The empty `fai.toml` makes the directory one
  workspace, so `PrimesParallel.fai` can use `Primes`.
- **Two kernels, one per binary.** The two binaries are compiled in different modes (below), and
  they want different code, much as other entries carry a kernel per architecture. Measured on
  Azure (Zen 5 / Zen 3 / Cobalt 100, six rounds each), against a single shared kernel:

  | Change | `primes` (1 thread) | `primes-parallel` (4 threads) |
  |---|---|---|
  | Sparse loop unrolled four times | +2.4% / +4.3% / +11.3% | −2.5% / −2.2% / −2.5% |
  | Sieve built while marking 3 | −0.7% / −1.6% / −0.9% | +2.4% / +2.2% / +1.4% |
  | Dense limit 32 instead of 16 | +8.5% / −1.9% / +1.5% | +2.5% / +3.5% / +3.7% |

  So `primes` uses `runSieve`: dense limit 16, the sieve allocated zeroed with `Array.repeat`,
  and the unrolled sparse loop `clearMultiples4`. With the inline array path, that loop is
  about 26 instructions per multiple against 30 for the plain one, and the four-way loop is
  still a single self-recursive function with no calls, so Fai still checks the array's
  ownership once per loop and not once per store. In this kernel's hot loops (`clearMultiples4`,
  `orPairs`, `orPattern`) every stored word is masked with `m`, a local bound to `0xFFFFFFFF`.
  Each word holds 32 bits, so the mask changes nothing, but it lets Fai's range analysis prove
  that the word fits a tagged integer. The store then skips its overflow-checked retag, about
  five instructions per multiple. A literal mask doesn't work, because the analysis only reads
  masks held in a local. Against the same build without the mask, the one-thread run gained
  5.5% on Zen 5, 6.6% on Zen 3 and 21.6% on Cobalt 100 (six rounds on Azure, 17 October 2026).
  `primes-parallel` uses `runSieveThreaded`:
  dense limit 32, the plain sparse loop (in the concurrent mode every array access is a runtime
  call, and the larger unrolled body only adds spills), and a sieve built by pushes while
  marking 3. That kernel starts from one zero word in an array with room for the whole sieve;
  the scan from 3 runs on it as on any sieve and finds 3, and marking 3 then pushes each later
  word from 3's pattern (built in the scratch with one OR per multiple), so each word is
  written once rather than zeroed and then ORed. 3 itself is cleared again and the scan goes
  on from 5.
- `Primes.fai` carries `example` and `forall` contracts (counts for small sizes, no even
  number above 2, no reported prime with an odd divisor up to its square root, counts equal to
  trial division up to 4999, pattern bits set exactly at the odd multiples of p, both kernels
  giving the same sieves and counts, every sieve bit equal to trial division), which
  `fai check` and `fai test` run. The `PRIMES_TEST` self-test checks the 13 sizes with both
  kernels in `primes`, then with the threaded kernel again in `primes-parallel`, as that binary
  compiles it.

Two things the standard runtime lacks are worked around. There is no exit status, so `main`
gets a small `Exit` capability over libc's `exit`. The only clock is `Clock.now`, wall-clock
milliseconds, so the run times are wall-clock and printed to the millisecond.

## Run

```sh
docker build -t primes-fai .
docker run --rm primes-fai
```

Or with Fai 0.1.0 and a C compiler (`fai build` links with `cc`) installed:

```sh
sh build.sh && ./run.sh
PRIMES_TEST=1 ./run.sh    # prime counts for sizes 1 to 10^8; exit 0 if all match
```

## Output

On a shared four-vCPU Intel Xeon container:

```
cauldnz-fai-base;6100;5.000;1;algorithm=base,faithful=yes,bits=1
cauldnz-fai-base;6880;5.002;4;algorithm=base,faithful=yes,bits=1
```

`primes` prints the line for one thread; `primes-parallel` prints one for all hardware
threads and, when there are more than four, one for exactly four.
