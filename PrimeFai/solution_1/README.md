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
  - **Factors below 16 (dense).** The odd multiples of `p` repeat every `p` slots. Each pass
    builds the pattern of four periods (`4p` slots, 128 multiples) in a scratch `Array Int`
    allocated with the sieve, with one read-OR-write per multiple, then ORs the pattern into
    the sieve slot by slot from the period that holds p², and clears the bit of `p` itself when
    the pattern set it. Each step reads a pattern slot once and ORs it into the same slot of
    two consecutive runs. Each array access is a runtime call (`fai_array_get_borrowed`,
    `fai_array_set`), so this costs 2.5 calls per slot against 2 per multiple, and pays below
    about p = 25. A local sweep found 16, 24 and 32 within the noise, with 16 ahead; two runs
    per step gained 8.5% over one at one thread.
  - **Factors of 16 and above (sparse).** Each multiple is set with its own read-OR-write, from
    p² in steps of 2p.
- A new array (and pattern scratch) every pass. Fai has no mutation in the language: the array is threaded through
  tail-recursive loops and, because it is uniquely owned, `Array.unsafeSet` updates it in place
  (Perceus reference counting). A debugger count of the runtime's copy path shows zero copies
  over the whole self-test.
- The multi-threaded runs start one independent sieve loop per task with `Async.parallel`;
  each task counts its own passes until the shared deadline.
- `Primes.fai` carries `example` and `forall` contracts (counts for small sizes, no even
  number above 2, no reported prime with an odd divisor up to its square root, counts equal to
  trial division up to 4999, pattern bits set exactly at the odd multiples of p), which
  `fai check` and `fai test` run.

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
sh build.sh && ./primes
PRIMES_TEST=1 ./primes    # prime counts for sizes 1 to 10^8; exit 0 if all match
```

## Output

On a shared four-vCPU Intel Xeon container:

```
cauldnz-fai-base;1845;5.001;1;algorithm=base,faithful=yes,bits=1
cauldnz-fai-base;7003;5.002;4;algorithm=base,faithful=yes,bits=1
```

The program prints one line for one thread, one for all hardware threads and, when there are
more than four, one for exactly four.
