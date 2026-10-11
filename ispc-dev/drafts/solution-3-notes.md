# Draft text: the third ISPC entry (wheel with precomputed tables)

Chris, 11 October, 16:30: submit the precomputed-tables wheel as a third entry,
`PrimeISPC/solution_3`, and say plainly that we're uneasy about it and why `solution_1` exists.
The climber builds the entry; these are the words for the two READMEs. House style: say what
it does and why, no more.

## For `PrimeISPC/solution_3/README.md`, near the top

> ### Why there are two ISPC wheels
>
> This entry and `solution_1` are the same wheel sieve. The difference is where some of the work
> happens. `solution_1` works everything out at run time, on every pass: where each prime's
> first multiple falls in each of the eight planes, and the bit pattern each small prime
> stamps across the sieve. This entry works those out once, when it is built, and reads them
> from tables. On our test machines that makes it about 20% to 24% faster on AMD Zen 3 and
> Zen 5, and about 14% faster on Arm.
>
> The rules allow it. A wheel may start from "a (pre)calculated set of prime numbers within a
> certain base number range", and the Zig wheel in `PrimeZig/solution_3` builds its tables at
> compile time and is tagged faithful. So this entry is tagged `faithful=yes` too.
>
> We're still a bit uneasy about it. The tables don't depend on the sieve size and every pass
> still sieves from scratch, but they do hold, ahead of time, the answers to questions the sieve
> would otherwise ask itself every pass. That feels closer to the line than we'd like, so we
> kept a version that doesn't do it. If you want the wheel that computes everything itself,
> `solution_1` is the one to look at; it is still about three times as fast as the fastest
> other wheel entry we measured. If the maintainers would rather this entry wasn't here, we're
> happy to withdraw it.

The existing Faithfulness section from `hc/champion-tables` follows, unchanged: it says exactly
what is generated, how big it is and what falls back to run time.

## For `PrimeISPC/solution_1/README.md`, in the Faithfulness section

> Nothing about the primes is worked out ahead of time: each pass finds every start position
> and builds every pattern itself. A version that reads those from tables generated at build
> time is `solution_3`; the rules allow it, and it is about 20% faster, but we wanted one wheel
> that does all its own work.

## Output labels

The two wheels need distinct labels so the leaderboard tells them apart, for example
`cauldnz-ispc-wheel` (solution_1) and `cauldnz-ispc-wheel-tables` (solution_3). Tags for both:
`algorithm=wheel,faithful=yes,bits=1`.

## For the PR description

> Three entries: a base sieve (`solution_2`), a wheel sieve that computes everything at run time
> (`solution_1`), and the same wheel reading build-time tables for start positions and small-
> prime patterns (`solution_3`). The third is allowed by the wheel rules, as in
> `PrimeZig/solution_3`; its README says what is precomputed and why we kept `solution_1` as
> well. Happy to drop `solution_3` if you'd prefer.
