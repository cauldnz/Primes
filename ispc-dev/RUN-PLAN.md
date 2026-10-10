# Run plan: scale, and one design in four languages (agreed with Chris, 2026-10-10 16:40)

Read this after `AUTOPILOT.md`. It sets this run's priorities, time box and end-of-run steps.
Everything else in the brief, the runbook and `HILL-CLIMB.md` still applies, including the
"Never without Chris" list. The previous plan is in git history; its results are in the morning
report of run ap-20261010T0140Z in `STATUS.md`.

## Limits

- Time box: 6 hours from the session start. Stop starting experiments at 5h15, so the final
  scoreboard and shutdown fit in the last 45 minutes. The Azure secret lasts until about
  06:30 AEST on 11 October.
- Azure: NZ$30 for the run, no new pools past NZ$25, Spot only, 128 Spot vCPUs in all. At most
  4 pools. Every pool's deadline is the run's end; take a pool down as soon as its work is done.
- New this run: one Intel size is allowed (Chris, 16:40), for the i7-9750H runner (priority 4).

## How this run works

As last run (ticks with `send_later` wake-ups, results through blob storage, background agents,
`st.py decide`, acceptance on the 95% interval), plus the new gates in `AUTOPILOT.md` 2d: a local
self-test and speed check before any submit, the compiled-code side-by-side with every profile,
no files over 2 MB in git, and no idle floor nodes between bursts. Last run's nodes were busy 31%
of the time; aim for 60%.

Background agents carry the porting work (priority 2) while Batch runs the scaling and wheel
work, so the run has two streams going at once. Two agents at most.

## State at the start

- `hc/champion` = `37e19c7`: wheel with hc-045; base with the NEON dense resetter (arm +2.5%).
- Base against Rust, 1T / all threads: Zen 5 +0.8% / +13.9%; Zen 3 +6.5% / +4.7%; Cobalt 100
  −1.9% / −1.5%; Zen 5 at 64 vCPUs +2.7% / +14.3%. With spare vCPUs (32 threads on 64) the lead
  is only +2.5%: it comes from full occupancy.
- Wheel: 2.3–3.0 times danielspaangberg's best faithful wheel; our Zig port of the same design is
  still 4.6% (Zen 5) to 7.6% (Zen 3) faster than the ISPC wheel.
- The base's sparse loop is at the base rules' floor (one byte read-modify-write per composite;
  `results/hc/asm-sparse/README.md`). One-thread base work is parked unless a profile shows a new
  lever.

## Priorities, in order

1. **Scale to 96 threads, and explain the full-occupancy lead.** The official multi-thread ranking
   runs all hardware threads (128 on the EPYC runner, 192 on the Threadripper).
   - One `D96as_v7` node (Zen 5, 96 vCPUs) on its own, inside the quota: our base, Rust, davepl's
     C++ and the Zig base at 1, 48 and 96 threads; then the same for our wheel, the Zig wheel and
     danielspaangberg's. Four rounds is enough for a scaling curve.
   - Why does Rust fall off when threads equal vCPUs? Test the obvious causes on a 16- or 32-vCPU
     node: the main thread's share of work, scheduler placement (try `taskset` and one thread per
     core), and allocation per pass. Record what explains it. If our entry does something that
     Rust doesn't, say what, in the README terms a reviewer would understand.
2. **One design in four languages: ports as entries.** Background agents write each port to
   submission standard: `Prime<Language>/solution_<next>/` with `README.md`, a `Dockerfile` that
   passes hadolint, the right tags, our self-test (`PRIMES_TEST=1` at every power of ten to 10⁸),
   and, for wheels, the 5,396-size count sweep. Port the design, not the ISPC code: each should
   read as good code in its own language.
   - **C++ base and C++ wheel** first. This answers Dave Plummer's C++ against Rust question with
     one design. Plain C++20, GCC from the distribution, `-O3 -march=native` like the existing C++
     entries. No intrinsics unless the existing C++ entries use them.
   - **Rust wheel** next (stable Rust, `-C target-cpu=native` like mike-barber's), then **Rust
     base**.
   - Measure every port in the same rounds as the ISPC and Zig versions of the same design, on
     Zen 5 and Zen 3: a table of ISPC, Zig, Rust and C++ for each design, at 1T and all threads.
   - A port that fails its self-test or its rules check is not measured. Keep each on its own
     `hc/port-<lang>-<entry>` branch; never touch an existing solution.
   - Note for Chris, in the morning report: CONTRIBUTING.md asks that a new solution with the
     same characteristics as an existing one be offered as an improvement to that solution
     instead. The C++ and Rust *wheels* are new ground (C++ has no wheel; Rust's only wheel is
     8-bit). The C++ and Rust *base* ports share their characteristics with existing entries
     (davepl's and mike-barber's), so say plainly how each compares and which route fits.
3. **Close the Zig-over-ISPC wheel gap.** Start with the compiled-code side-by-side of the two
   sparse loops and the per-prime set-up, on one Zen 5 node, as 2d asks. Then one change at a time.
4. **Intel.** One Intel size as a stand-in for the i7-9750H. Every current Intel Xeon size has
   AVX-512 and the i7 doesn't, so build every entry for an AVX2-only target on that node (ISPC
   `avx2-i32x16` only, `-march=skylake` for C++ and Zig, `-C target-cpu=skylake` for Rust) and say
   so in the results. Our base and wheel against Rust and davepl's C++, 1T and all threads, six
   rounds. A measurement, not an experiment: no keep or revert.
5. **Arm, if time remains.** Rust's lead on Cobalt 100 is about 1.9%. Only with a profile that
   names the phase.

## Morning report additions

Besides the usual report (section 9 of `AUTOPILOT.md`):
- **Decisions and why**, from the `st.py decide` records.
- The scaling curves (1 to 96 threads) for both designs and what explains the full-occupancy lead.
- The four-language table for each design, with each port's branch, self-test and rules status.
- The route for each port (new solution, or an improvement to offer an existing author).
- Intel numbers, and how they compare with the official i7 results.
- The overhead split and the busy share of node time.
