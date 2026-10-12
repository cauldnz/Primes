**Title:** Base algorithm: two questions on clearing order

Two questions about the base rules, for the base entry in #PR. That PR doesn't depend on the
answers. As submitted, it clears all of a factor's multiples in one upward sweep, starting from
the period of the sieve that holds p², before it looks for the next factor. For small factors
the sweep works through whole periods, a vector of consecutive words at a time. If either change
below is allowed, I'll send it as a small follow-up PR.

**The entry.** An ISPC base sieve (`PrimeISPC/solution_2`, in #PR), tagged
`algorithm=base,faithful=yes,bits=1`: one bit per odd number, factors found by scanning the sieve,
each multiple cleared by its own single-bit OR, stepping 2 × factor. It reports one thread and
several multi-thread lines, one independent sieve per thread.

### Question 1: does the rule mean upward only?

The rule says the algorithm "clears all non-primes individually, increasing the number with
2 * factor on each cycle." Read plainly that is upward, and I'm happy to keep it so. I'm asking
whether the direction is the point of the rule or just a description, because a downward sweep
for every second factor visits exactly the same multiples:

```
for (each factor p, in the order the outer loop finds them, k = 0, 1, 2, ...):
    if k is even: for (m = p*p; m <= limit; m += 2*p) clear(m)
    else:         for (m = largest odd multiple of p <= limit; m >= p*p; m -= 2*p) clear(m)
```

This applies to every factor. The gain is cache locality: each sweep starts where the last one
ended, still in L1.

### Question 2: may the large factors be cleared in blocks?

```
for (each factor p, as the outer loop finds it):
    if p < 128: clear all of p's multiples
    else:       clear p's multiples in the first 16KB block; remember where p stopped
for (each later 16KB block):
    for (each factor p >= 128, in order): clear p's multiples in this block, from where it stopped
```

Finding factors still runs in order, ahead of clearing. What changes is that the clearing of the
large factors is finished block by block afterwards, rather than one factor at a time. Two base
entries already do this:

- mike-barber's `PrimeRust/solution_1`, variant `striped-blocks` (16KB and 4KB blocks), which
  reports `mike-barber_bit-storage-striped-blocks;...;algorithm=base,faithful=yes,bits=1`;
- rogiervandam's `PrimeC/solution_5`, `shakeSieve` in `src/sieve_base.c`, which loops over 32KB
  blocks and, within each, over every factor, and reports `rogiervandam_base;...;algorithm=base,faithful=yes,bits=1`.

Is the version above base on the same footing as those?

### Why it matters

At 1,000,000 a one-bit sieve of odd numbers is 61 KiB, and a base entry can't make it smaller.
The fastest data cache is 32 KB on most x86 cores and 48 KB on Zen 5, so every upward sweep
pushes the start of the sieve out of cache before the next sweep needs it. I ran the entry unchanged at sixteen
sieve sizes on Zen 3, Zen 5 and Cobalt: on Zen 5 its throughput per number holds steady up to
about 47 KB and falls 21% by 61 KB. On Cobalt (64 KB cache) it sits just inside and the step
comes past 64 KB. Neither change shrinks the sieve; both only change which part of it is being
worked on, so the part in use stays in cache.

### Context

The entry as submitted is in #PR. Each change on top of it: [alternating](https://github.com/cauldnz/Primes/tree/hc/f1-alternate/PrimeISPC/solution_2)
and [blocked](https://github.com/cauldnz/Primes/tree/hc/f2-block-16/PrimeISPC/solution_2), in
`primes_base.ispc`. Measured on the code in #PR, alternating adds 13.9% on Zen 5 and 10.0% on
Zen 3 at one thread (6 paired rounds each); blocking adds 10.8% on Zen 5 and
10.6% on Zen 3 (7 paired rounds each). That's why I'd like a ruling rather than guess either way. The size measurements are in
[`results/hc/size-cliff`](https://github.com/cauldnz/Primes/tree/ispc-dev/ispc-dev/results/hc/size-cliff).

### What I'd submit

I'll follow whatever you decide, and anything ruled out stays out of the base entry:

| Q1 | Q2 | What gets submitted as base |
|---|---|---|
| no | no | the plain upward loop, no blocks |
| no | yes | blocks for the large factors, upward within each block |
| yes | either | alternating direction (blocking adds little on top of it) |
