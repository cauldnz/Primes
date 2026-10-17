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
  - **Dense factors (below 16).** The odd multiples of `p` repeat every `p` slots. Each pass
    builds the pattern of four periods (`4p` slots, 128 multiples) in a scratch `Array Int`
    allocated with the sieve, with one read-OR-write per multiple, then ORs the pattern into
    the sieve slot by slot from the period that holds p², and clears the bit of `p` itself when
    the pattern set it. Each step reads a pattern slot once and ORs it into the same slot of
    two consecutive runs.
  - **Sparse factors (the rest).** Each multiple is set with its own read-OR-write, from p² in
    steps of 2p, four multiples per loop step (each still its own read-OR-write). The loop is
    a single self-recursive function with no calls, so Fai compiles it as a loop that checks
    the array's ownership once, not once per store.
- A new array (and pattern scratch) every pass. Fai has no mutation in the language: the array
  is threaded through tail-recursive loops and, because it is uniquely owned, `Array.unsafeSet`
  updates it in place (Perceus reference counting). A debugger count of the runtime's copy path
  shows zero copies over the whole self-test.
- **Threads are processes, started through Fai's process capability.** Fai 0.1.0 compiles a
  whole program in a "concurrent" mode when the effects of `main` include `Concurrency`, and
  that mode turns off the inline array fast path: every `Array.unsafeGet` and `Array.unsafeSet`
  becomes a runtime call (in the compiler, `crates/fai-codegen/src/emit.rs`, `array_prim`),
  about 2.9 times slower per thread. Starting a native process needs only the
  `ProcessHost.Process` capability, not `Concurrency`, so `primes-parallel`
  (`PrimesParallel.fai`) adds `ProcessHost.native` to its runtime record, starts `primes
  --worker <deadline>` once per thread (each child runs the same single-threaded worker until
  the shared deadline and prints its passes and first prime count), reads the outputs and adds
  them up. Neither program has `Concurrency` in its effects, which `fai query caps` confirms,
  so every thread runs the inline kernel. The time printed runs from before the first child
  starts to after the last one is read. On a shared four-vCPU container this gave 3.4 times
  the four-thread passes of the earlier `Async.parallel` version (median of five interleaved
  runs, 18824 against 5480). The empty `fai.toml` makes the directory one workspace, so
  `PrimesParallel.fai` can use `Primes`.
- `Primes.fai` carries `example` and `forall` contracts (counts for small sizes, no even
  number above 2, no reported prime with an odd divisor up to its square root, counts equal to
  trial division up to 4999, pattern bits set exactly at the odd multiples of p, the sparse
  loop's bits, every sieve bit equal to trial division), which `fai check` and `fai test` run.
  The `PRIMES_TEST` self-test checks the 13 sizes in `primes`, which is also the program each
  parallel worker runs.

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
cauldnz-fai-base;6145;5.000;1;algorithm=base,faithful=yes,bits=1
cauldnz-fai-base;18824;5.001;4;algorithm=base,faithful=yes,bits=1
```

`primes` prints the line for one thread; `primes-parallel` prints one for all hardware
threads and, when there are more than four, one for exactly four.
