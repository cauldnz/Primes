# Draft plan for the next run: base first

Workshop draft, 10 October. It replaces the "Next run" list at the end of `RUN-PLAN.md` when
`harness/ticks` merges. Chris, 09:58: the next runs focus on the base entries, because a high
place on the base leaderboard is what shows the machine competing with human experts.

## Where the base entry stands (final3/final4, 1T / all threads, against mike-barber's Rust)

| Machine | ISPC base | Rust | Gap |
|---|---|---|---|
| Zen 3 (AVX2) | 56.0k / 432k | 52.5k / 412k | +7% / +5% |
| Zen 4 (AVX-512) | 82.9k / 656k | 76.5k / 608k | +8% / +8% |
| Zen 5 (AVX-512) | 128.1k / 1.02M | 125.6k / 880k | +2% / +16% |
| Cobalt 100 (arm64) | 41.1k / 164k | 42.9k / 171k | −4% / −4% |

The official runners are a Zen 5 Threadripper, an AVX2-only EPYC VM, an Intel i7-9750H, an
SSE4-only Celeron and a Raspberry Pi 4. We have measured two of those five kinds of machine.

## Priorities, in order

0. **Ground the harness against the leaderboard first** (Chris, 10:13). Run the top ten faithful
   1-bit base entries in our harness and check that it ranks them the way the official runners
   do. If it doesn't, a win in our harness may not be a win on the leaderboard, and everything
   after this is built on sand. The ten, from `results/leaderboard-2026-10-09b.md` (the
   solutions that appear most often in the runners' top tens):

   | Solution | Best label | Official, Threadripper 1T |
   |---|---|---|
   | `PrimeRust/solution_1` | mike-barber_bit-unrolled-hybrid | 118,846 (#2) |
   | `PrimeSwift/solution_1` | yellowcub_fahlman_striped_UInt8 | 122,869 (#1; AVX2 only) |
   | `PrimeChapel/solution_1` | GordonBGood_extreme_hybrid | 117,862 (#4) |
   | `PrimeNim/solution_3` | GordonBGood_extreme-hybrid | 106,968 (#5) |
   | `PrimeHaskell/solution_2` | GordonBGood_extreme-hybrid | 105,845 (#6) |
   | `PrimeJulia/solution_4` | GordonBGood_extremehybrid | 84,564 (#7) |
   | `PrimeD/solution_3` | serg-gini_bit-unrolled-hybrid | 69,449 (#8) |
   | `PrimeV/solution_2` | GordonBGood_extreme-hybrid | 67,598 (#10) |
   | `PrimeCPP/solution_5` | davepl_array_optimized | all-threads line only |
   | `PrimeAssembly/solution_4` | (best faithful base line) | top ten on several runners |

   How: build each from its own Dockerfile on upstream `drag-race` (pin the commit). Zen 5
   (`D16as_v7`) stands in for the Threadripper and Zen 3 (`D16a_v4`) for the EPYC VM; Cobalt 100
   for the Pi 4 where an entry builds on arm64 (Swift is AVX2-only: skip it there). Five counted
   rounds plus a warm-up, interleaved, 1T and all threads; skip the half and quarter thread
   counts here. Output: a table of each entry's passes in our harness against the official
   number, the rank in each, and the ratio. A rank correlation that holds, and ratios within
   about 10% between neighbours, means the harness is fit to judge. Where it isn't, say which
   entries move and why (thread count, SMT, CPU model, compiler flags) before any experiment.

   **Keep the overhead down** (Chris, 10:46). Pool start-up, node boot, image builds and idle
   nodes are paid for but measure nothing. Rules for the sweep:
   - **No separate pools.** The sweep is the first task on the run's own pools, one node per
     machine type, so its boot and start task are shared with the rest of the run. The nodes
     stay up for priority 1; nothing scales down between the sweep and the profiling.
   - **One task per machine.** One task builds and runs every entry on its node, so each machine
     boots once. Don't fan the entries out across nodes: the sweep needs about 15 minutes of
     measuring per machine, less than a second boot and build would cost.
   - **Build in parallel, once per node.** Pull the base images and build the entries four at a
     time (`xargs -P 4`). The start task already builds Rust and davepl's C++; reuse those
     images. If an entry doesn't build in 20 minutes, drop it and say so.
   - **Don't share images across CPU types.** Several entries compile for the build machine's CPU
     (`-march=native` and similar), as the official runners do. An image built on Zen 3 and run
     on Zen 5 would lose AVX-512 and understate the entry. Build on each machine type.
   - **Stream results as they come**, one entry and round at a time, so a pre-empted node's
     rounds can be salvaged rather than rerun.
   - **Account for it.** Report node-minutes for the sweep split into boot and start task,
     builds, measuring and idle, from the task log and the cost log. Aim for measuring to be at
     least 60% of the sweep's node-minutes. Spend for the sweep should be well under NZ$2.

1. **Profile the base on every machine first** (harness backlog item 1, still open for base):
   phases for ours and Rust on one node each, Zen 3, Zen 5 and Cobalt 100. Every later
   hypothesis names its phase and the share at stake.
2. **Zen 5 at one thread.** The Threadripper is the headline runner and our lead there is 2%.
   Widen it.
3. **Arm.** We trail Rust by 4% on Cobalt 100 and the Pi 4 is a Cortex-A72, weaker still.
   Close the gap on Cobalt; if a Neoverse N1 size (Ampere) is available, add it as the nearer
   proxy for the Pi.
4. **The runners we haven't measured.** An SSE4-only build (`ISPC_TARGETS=sse4-i32x8`) against
   Rust's SSE4 path on Zen 3, as a proxy for the Celeron. An Intel AVX2 size for the i7-9750H
   (backlog item 6) only with Chris's OK.
5. **Thread scaling.** All threads at 32 and 64 vCPUs on Zen 5, one large node at a time, within
   the 128-vCPU Spot quota. Look at per-pass allocation and SMT.
6. Only then, wheel work: the Zig wheel's lead and the Rust wheel port, from the climber's own
   list at the end of `RUN-PLAN.md`.

Ports of the base design to C++ and Rust stay on the list for the like-for-like comparison, after
these.
