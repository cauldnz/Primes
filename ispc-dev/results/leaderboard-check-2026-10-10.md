# Does our hardware reproduce the leaderboard? (2026-10-10)

Chris asked whether our Zen nodes rank the leaderboard's entries the way the official runners do.
The `board` task built the top 10 faithful 1-bit base entries at 1T from upstream `drag-race` on
one Zen 5 node (`D16as_v7`, EPYC 9V45) and one Zen 3 node (`D16a_v4`, EPYC 7763), ran each
image's default command as the official benchmark does, three scored rounds, with our two
entries and the C, C++ and wheel rivals alongside. Raw output and the full tables:
`results/hc/board-2026-10-10/`.

## 1T, faithful 1-bit base: official runner against ours (passes in 5 s, median)

| Entry | Threadripper 9995WX (runner 73) | our Zen 5 | Δ | EPYC VM (runner 74) | our Zen 3 | Δ |
|---|---|---|---|---|---|---|
| Swift (yellowcub) | 122,869 (1st) | 103,837 (5th) | −15% | 59,829 (3rd) | 43,259 (6th) | −28% |
| Rust unrolled (mike-barber) | 118,846 (2nd) | 117,482 (1st) | −1% | 62,724 (2nd) | 52,101 (2nd) | −17% |
| Rust extreme (mike-barber) | 118,574 (3rd) | 116,282 (2nd) | −2% | 63,144 (1st) | 52,422 (1st) | −17% |
| Chapel (GordonBGood) | 117,862 (4th) | 106,981 (3rd) | −9% | 52,223 (5th) | 47,489 (4th) | −9% |
| Nim (GordonBGood) | 106,968 (5th) | 106,615 (4th) | −0% | 52,401 (4th) | 50,398 (3rd) | −4% |
| Haskell (GordonBGood) | 105,845 (6th) | 94,689 (6th) | −11% | 51,426 (6th) | 43,887 (5th) | −15% |
| Julia (GordonBGood) | 84,564 (7th) | 68,205 (7th) | −19% | 41,283 (7th) | 35,733 (7th) | −13% |
| D unrolled (serg-gini) | 69,449 (8th) | 55,643 (10th) | −20% | 29,769 (10th) | 28,689 (9th) | −4% |
| D extreme (serg-gini) | 69,219 (9th) | 55,785 (9th) | −19% | 30,768 (9th) | 28,469 (10th) | −7% |
| V (GordonBGood) | 67,598 (10th) | 57,258 (8th) | −15% | 33,739 (8th) | 32,227 (8th) | −4% |
| *ours: ISPC base* | not on the board | **119,803** | | not on the board | **56,012** | |

## What it shows

- **The same ten entries, nearly the same order.** On Zen 5 the top ten are the Threadripper's
  ten; only Swift moves far (1st there, 5th here) and D and V swap. On Zen 3 against the EPYC VM,
  the top two (Rust) match and Swift again drops (3rd to 6th).
- **Our Zen 5 node is a fair stand-in for the Threadripper at 1T for some entries, not all.** Rust
  and Nim land within 2% of the official numbers; Chapel, Haskell, Julia, D, V and Swift run 9–20%
  slower here. The EPYC VM is faster than our Zen 3 for everything (Rust by 17%), so it is not a
  Zen 3; its "EPYC Processor" label hides the model.
- **Swift is the outlier,** 15% (Zen 5) and 28% (Zen 3) slower here than on the official runners,
  far more than any other entry. Possible causes, not tested: a newer Swift toolchain on the day of
  the official run, or a build that picks up CPU-specific code there.
- **Where our entries would sit.** The ISPC base, at 119.8k on our Zen 5, is above both Rust
  variants here. If it tracks the Threadripper as Rust does (within 2%), it would be about 2nd at
  1T on runner 73, behind Swift's 122.9k. So Swift, not Rust, is the base entry to beat on the
  Zen 5 runner, and we can't reproduce Swift's speed on our nodes. The wheel (195.9k on our Zen 5)
  is far above every faithful 1-bit entry in any category.
- rogiervandam's C ran 128.9k on our Zen 5 against 110.6k on the Threadripper (+17%): the opposite
  direction from everything else.

Notes: davepl's C++ prints only an all-threads line by default, and Swift only a 1T line, so each
is missing from one table. Thread counts differ (16 vCPUs here, 192 and 128 there), so the
all-threads tables are not comparable with the official ones.
