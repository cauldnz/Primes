# Rules note

This build stretches two parts of the base rule in `CONTRIBUTING.md`.

**Blocked sparse phase.** The base rule says "the algorithm uses an outer loop, in which two
operations are performed: 1. searching for the next prime in the sieve, and 2. clearing this
prime's multiples in the sieve". For factors from 128 up, the outer loop clears each prime's
multiples only in the first 16KB block of the sieve; a second loop then takes the remaining
blocks in turn and lets every one of those primes clear its multiples in each, one composite at
a time and stepping 2 * factor, so the clearing of a prime is split across blocks.
rogiervandam's `PrimeC/solution_5` (`shakeSieve` in `src/sieve_base.c`, tagged
`algorithm=base`) does the same for every factor, small ones included, over 32KB blocks.

**Alternating sweep direction.** The base rule says the clearing loop "clears all non-primes
individually, increasing the number with 2 * factor on each cycle". This build clears every
composite individually with a step of 2 × factor, but every second factor runs the loop
downwards, so the number decreases by 2 × factor on each cycle: below 128 over the whole sieve,
from the last multiple below the sieve end down to factor × factor, and from 128 up inside each
block, from the last multiple below the block end down to the first one in the block. Factor 3
always runs upwards, and the set of composites cleared per factor is the same as in the upward
form.
