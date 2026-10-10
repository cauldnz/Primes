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
