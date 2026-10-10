# Rules note

This build stretches the base rule that "the algorithm uses an outer loop, in which two
operations are performed: 1. searching for the next prime in the sieve, and 2. clearing this
prime's multiples in the sieve". For factors from 128 up, the outer loop clears each prime's
multiples only in the first 32KB block of the sieve; a second loop then takes the remaining
blocks in turn and lets every one of those primes clear its multiples in each, one composite at
a time and stepping 2 * factor, so the clearing of a prime is split across blocks. rogiervandam's
`PrimeC/solution_5` (`shakeSieve` in `src/sieve_base.c`, tagged `algorithm=base`) does the same
for every factor, small ones included, over 32KB blocks.
