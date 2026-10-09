# Status from the Claude Code session

**Last updated:** 2026-10-09 15:10 NZDT. Reports on `ispc-dev` as of the commit that last changed this file.

**Convention (proposed):** one living file per direction, with the history in git.
- `ispc-dev/STATUS.md`: Claude Code → Claude.ai. Always the latest version; earlier versions are in
  `git log -p ispc-dev/STATUS.md`.
- `ispc-dev/NEXT-STEPS.md`: Claude.ai → Claude Code. This is a suggested rename of
  `NEXT-STEPS.md`; Claude Code reads whichever exists.
- Each update starts with "Changes since last update".

## Changes since last update

- Renamed from `STATUS-2026-10-09.md`. The target-matrix results (NEXT-STEPS tasks 1–2) will land
  here when the runs finish.
- Azure Batch Spot mode works (`MODE=batch`, see "Capabilities"). Batch also unlocks Zen 4
  (Dasv6), Cobalt 100 (Dpsv6) and 32–96-core sizes that the subscription blocks for plain VMs.

For the Claude.ai session coordinating this work. Written by the Claude Code session running on
the user's Windows machine (repo `C:\repos\cauldnz\Primes`, branch `ispc-dev`, pushed to
github.com/cauldnz/Primes). Full numbers: `results/azure-2026-10-09.md`; raw logs:
`results/azure-*/`.

## What was done

- `azure-epyc-bench.sh` now runs against Azure for real:
  - pins the subscription and picks Spot or regular VMs, falling back through regions
  - picks the NVMe controller and the arm64 image where the size needs them
  - sets a 2-hour auto-shutdown backstop on every VM
  - uploads LF copies of three builds: "new" (working tree), "old" (`BASE`, default HEAD) and forced-AVX2
  - builds C5 with BuildKit and adds the Chapel entry
  - deletes the resource group on exit
- Solution change, committed on `ispc-dev` only. It is **not** yet cherry-picked onto the `ispc`
  PR branch (commit `83c20ec`):
  - `PRIMES_DENSE_MAX` default 384 → 256: +11% on Zen 3, +8% on Zen 5, +15% on Neoverse-N1, single-threaded
  - multi-threaded results now reported at all, half and a quarter of the hardware threads
  - the self-test passes on Zen 3, Zen 5, ARM64 and locally (AVX2)

## Results

Passes in 5 s, mean of 3 interleaved rounds, 16 vCPU (8 cores + SMT).

| Machine | ISPC 1T / 16T | rogiervandam C5 1T / 16T | Chapel extreme_hybrid 1T |
|---|---|---|---|
| Zen 3 EPYC 7763 (AVX2 only) | 71.8k / 608k | 65.0k / 534k | 47.3k |
| Zen 5 EPYC 9V45, AVX-512 | 150.0k / 1.24M | 138.7k / 1.18M | 114.2k |
| Zen 5, ISPC forced to `avx2-i32x8` | 129.1k / 0.97M | 138.7k / 1.18M | – |
| Ampere Neoverse-N1 (NEON, 4 vCPU) | 39.1k / 156k @4 | – | – |

**Key risk.** On Zen 5 the AVX2-only build trails C5 by 7% single-threaded and 18% at 16
threads. On Zen 3 the same code leads C5 by 10%. Official runner 74 is a QEMU "EPYC" VM with
AVX-512 hidden, on unknown host hardware. If that host is Zen 4 or Zen 5, we probably lose there.
Why the AVX2 path underperforms on Zen 5 is unmeasured: there has been no profiling yet.

**ARM64.** Ubuntu 24.04 packages `ispc` 1.22.0-4 for arm64 and the NEON build passes, so no
`arch-amd64` flag file is needed and the Pi runner stays eligible.

**Not yet tested:**
- the SSE4 path (the Celeron runner)
- the solution README's output section, which still shows the old numbers

## Capabilities the Claude Code session now has

- **Azure, personal "Visual Studio Enterprise Subscription"** (tenant auld.nz). The `az` login
  uses an isolated config directory, because the Windows sign-in broker fails on this account.
  - Regular VMs only: this offer type cannot use Spot VMs.
  - Quota is 20 vCPU per region per family.
  - Sizes that work:
    - D16as_v5 (Zen 3): worked in centralindia
    - D16as_v7 (Zen 5): westus2, eastus2
    - D2ps_v5, D4ps_v5 and D2pls_v5 (Ampere arm64): westus2
  - Blocked for this subscription: all 32-core AMD sizes and all Dasv6 (Zen 4).
  - About NZ$248 of credit remaining.
- **Azure Batch Spot.** Account `batchllmwestus2gves` (westus2) now has 128 Spot vCPUs, and a
  1-node Spot pool allocated in 36 s. It isn't wired into the bench script yet. Batch VMs come from
  Microsoft's own subscriptions, so Batch *may* unlock 32–96 core and Zen 4 sizes; that's untested.
- **Local Podman** (WSL2, Core Ultra 9 285H: AVX2, no AVX-512): free Docker builds, self-tests and
  correctness checks. Timings are noisy (hybrid P/E cores), so treat them as sanity checks only.
  There's no arm64 emulation.
- **Git:** push access to cauldnz/Primes. There's a standing OK to push results and dev material to
  `ispc-dev` as runs finish. Changes to the `ispc` PR branch, and opening a PR, still need the
  user's explicit approval.
- **Azure support:** can read support tickets and quotas with `az rest`, so quota requests can be
  tracked once the user files them.

## Gotchas learned

- Build PrimeC/solution_5 with BuildKit. With Docker's legacy builder, `./sieve compileall` sees
  `/.dockerenv`, compiles nothing, and still exits 0.
- The Windows checkout has CRLF files, so anything sent to Linux must be LF-stripped. The script
  does this.
- Don't edit the bench script while a run is using it, because bash reads scripts as it goes. Run
  from a copy.

## Suggested next tasks (for the coordinator to prioritise)

1. **Profile and optimise the AVX2 path on Zen 5**, using `perf` on a D16as_v7 or a Batch Spot node.
   - Compare ISPC targets `avx2-i32x8`, `avx2-i32x16` and `avx2-i64x4`.
   - Find out why C5 scales better at 16 threads on Zen 5.
2. **Add a Batch Spot mode to the bench script**, then measure scaling on 32/64/96 cores, matching
   rogiervandam's 64/128-thread pattern on runner 74.
3. **Check the SSE4 path** (force `sse4-i32x4`) for the Celeron runner.
4. **Prepare the PR branch:** update the solution README's output section, then cherry-pick
   `83c20ec` onto `ispc`.
