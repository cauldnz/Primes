# fai-000/fai-001: edit-check-test cycles

Fai 0.1.0 on a shared four-vCPU Intel Xeon container. Wall-clock seconds are for the command
alone, measured with `date +%s.%N` around it. The daemon was warm after the first command.
Times of day are the container's clock (UTC).

## Headline

- First write of `PrimeFai/solution_1/Primes.fai` to its first passing `PRIMES_TEST=1`: under
  one minute. The file was written between 23:41:47 and 23:42:23 and the self-test passed at
  23:42:38, so 15 to 51 seconds. Counting from 23:40:49, when sieve work began (after the
  feasibility probes, before the exit-status probe), it was 109 seconds.
- That took four cycles: `fai check`, `fai test`, `fai build`, self-test. None failed.
- Over the whole session: no type errors, no effect errors and no layout errors. The one
  failure on the real source was `fai fmt --check` (layout drift, fixed by `fai fmt`). Every
  other failure below was a deliberate mutant, run to see which layer catches a sieve bug.

## Cycles on the solution

| # | Time | Command | Wall s | Result | Caught by |
|---|---|---|---|---|---|
| c1 | 23:42:23 | `fai check Primes.fai` (64 bits/element) | 0.23 | ok, 19 examples pass | - |
| c2 | 23:42:27 | `fai test Primes.fai` | 0.24 | 23/23 contracts pass | - |
| c3 | 23:42:32 | `fai build --release` (AOT) | 0.93 | ok | - |
| c4 | 23:42:38 | `PRIMES_TEST=1 ./primes` | 2.02 | 13/13, exit 0 | - |
| c5 | 23:42:54 | `./primes` (timed run) | 10.02 | 429 passes 1T, 1,699 4T | timing: slow (see v32) |
| v32 | 23:44:38 | build of the 32 bits/element variant | 1.07 | ok; self-test 13/13; 1,097 passes 1T | timing: 2.5 times faster, adopted |
| v62 | 23:45:16 | build of a 62 bits/element variant (`/` and `%` by 62) | 1.04 | ok; self-test 13/13; 969 passes 1T | timing: slower than 32, dropped |
| c6 | 23:45:35 | `fai build --release` (32 bits) | 0.92 | ok | - |
| c7 | 23:45:39 | `fai fmt --check` | 0.01 | fail: "would reformat" | formatter (layout) |
| c8 | 23:45:44 | `fai fmt` | 0.02 | reformatted | - |
| c9 | 23:46:07 | `fai fmt --check` after tidying three wrapped lines | 0.01 | ok | - |
| c10 | 23:46:12 | `fai check` | 0.27 | ok | - |
| c11 | 23:46:13 | `fai test` | 0.22 | 24/24 contracts pass | - |
| c12 | 23:46:31 | `fai build --release` | 0.82 | ok | - |
| c13 | 23:46:32 | `PRIMES_TEST=1 ./primes` | 0.90 | 13/13, exit 0 | - |
| c14 | 23:49:04 | `sh build.sh` (`--no-daemon`) | 0.54 | ok | - |
| c15 | 23:49:06 | `PRIMES_TEST=1 ./primes` | 0.93 | 13/13, exit 0 | - |

## Deliberate mutant (start clearing at p²/2 + 1 instead of p²/2)

| # | Time | Command | Wall s | Result | Caught by |
|---|---|---|---|---|---|
| m1 | 23:46:20 | `fai check` | 0.19 | 6 examples fail (`FAI6001`) | `example` contract |
| m2 | 23:46:23 | `fai test` | 0.23 | 6 examples and 1 `forall` fail; counterexample n = -1 | `example` and `forall` contracts |
| m3 | 23:46:37 | `fai build` | 0.73 | builds | - |
| m4 | 23:46:38 | `PRIMES_TEST=1 ./primes` | 1.14 | 10 of 13 sizes wrong, exit 1 | self-test |

The mutant is caught by `fai check` in 0.19 seconds, before any build. The `FAI6001` report
gives the line of the failing example but not the two values it compared.

## Feasibility probes (scratch programs, not committed)

| Time | Command | Wall s | Result |
|---|---|---|---|
| 23:40:23 | `fai check Probe.fai` | 0.02 | ok |
| 23:40:26 | `fai build Probe.fai` | 1.03 | ok (array, bit-op and loop probes) |
| 23:41:23 | `fai build Abort.fai` | 1.01 | ok; an out-of-bounds `unsafeGet` aborts with exit 134 |
| 23:41:47 | `fai build Exit.fai` | 0.83 | ok; `foreign "exit"` gives exit status 3 |

## Counts by category

| Category | Count |
|---|---|
| Cycles run on the solution (check, test, fmt, build, self-test, timed run) | 15 |
| Variant builds tried for speed | 2 |
| Mutant cycles | 4 |
| Probe cycles | 4 |
| Errors caught by the type checker | 0 |
| Errors caught by effects | 0 |
| Errors caught by `example`/`forall` (mutant only) | 2 cycles (m1, m2) |
| Errors caught by the self-test (mutant only) | 1 (m4) |
| Found only by timing or output | 1 (64-bit elements box: 429 against 1,097 passes) |
| Formatter drift | 1 (c7) |
