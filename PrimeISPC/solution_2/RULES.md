# Rules note

The base algorithm in `CONTRIBUTING.md` says the clearing loop "clears all non-primes
individually, increasing the number with 2 * factor on each cycle". This solution clears every
composite individually with a step of 2 × factor, but every second factor runs the loop from the
last multiple below the sieve end down to factor × factor, so the number decreases by 2 × factor
on each cycle. The outer loop, the factor search and the set of composites cleared per factor
are the same as in the upward form.
