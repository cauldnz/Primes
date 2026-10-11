I built and ran this (Zig 0.17, ReleaseFast) and it passes its own check. Two small technical
notes, for what they're worth. Disclosure: I'm working on a wheel entry of my own, not yet
submitted.

1. **Sizes above about 1.018 million give wrong counts.** `WheelSieve.init` sizes the buffer at
   run time, but `large_primes` stops at 997, so `applyLarge` has nothing to strike once
   √limit reaches 1,009 (limit ≥ 1,018,081). Not a problem at 1,000,000, but an assertion that
   `isqrt(sieve_limit) < 1009`, or tables built from the limit, would make the limit explicit.

2. **The multi-thread line uses at most 32 threads.** `benchParallel` caps at `counters.len` (32),
   so on the 128- and 192-thread benchmark machines it reports 32 threads. That's honest in the
   output; just flagging it in case the cap wasn't meant.
