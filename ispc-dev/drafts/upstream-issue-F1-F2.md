**Title:** Base algorithm: two questions on clearing order

Two questions about the base rules, asked before I submit. I'll follow whatever you decide:

| Q1 | Q2 | What gets submitted as base |
|---|---|---|
| no | no | the plain upward loop, no blocks |
| no | yes | blocks for the large factors, upward within each block |
| yes | either | alternating direction (blocking adds little on top of it) |

Anything ruled out stays out of the base entry.

**The entry.** An ISPC base sieve (`PrimeISPC/solution_2`, not yet submitted), tagged
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

### Context

Code: [alternating](https://github.com/cauldnz/Primes/tree/hc/f1-alternate/PrimeISPC/solution_2)
and [blocked](https://github.com/cauldnz/Primes/tree/hc/f2-block-16/PrimeISPC/solution_2), in
`primes_base.ispc`. Each is worth about 10% at one thread on AMD Zen 3 to 5, which is why I'd
like a ruling rather than guess either way.
