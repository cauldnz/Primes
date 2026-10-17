# Run 10 (and run 9) evidence for "Do agent-specific programming languages help?"

Sources are on `ispc-dev` unless marked. Run 10 = `ap-20261011T1929Z` (19:30-23:49 UTC, 11 Oct;
4.35 h of a 6 h box). Run 9 = `ap-20261011T0645Z` (06:44-12:15 UTC, 11 Oct). The C++, Rust and
Zig ports were *built* earlier (Rust/C++ in `ap-20261010T0715Z`, Zig in `ap-20261009T1112Z`) and
*climbed* in run 9. EVENTS times are UTC.

## 1. Correctness: mistakes caught per stage (run 10)

| Stage | Plain OCaml | OxCaml | Source |
|---|---:|---:|---|
| Compile / type errors in candidates | not recorded | not recorded | No EVENTS line, ledger note or fix-up commit mentions one; each `hc/ox-*`/`hc/ocaml-*` branch adds 1-2 commits over its parent (`git rev-list --count`), so agents' failed builds left no trace |
| Toolchain errors met while probing | 0 | 2 | OXCAML-NOTES (ox-001): AVX-512 load with `-favx512f` crashes the emitter (`Fatal_error ... unaligned vec512`); link fails with `undefined reference to caml_sse_vec128_or` until dummy C stubs are linked |
| Local self-test failures | not recorded | not recorded | EVENTS only record passes ("rebuilt here, PRIMES_TEST=1 exits 0" on every submit, e.g. 20:12, 20:21, 21:04, 23:11) |
| Local-gate rejects (never sent to Azure) | 2 (ocaml-006 Bigarray −8%; ocaml-007 32-bit stores −38%) | 3 (ox-013 −6/−7%; ox-015 −1.5%; dense-limit sweep parked, +1.3% "inside noise") | EVENTS 21:09, 23:13, 21:48, 21:57, 20:52; LEDGER r10-ocaml-006/-007, r10-ox-013/-015; RETRO run 10 "five candidates stopped at the local gate" |
| Azure build failures (code) | 0 | 0 | No failed build lines in `results/hc/ox-*`, `ocaml-*`, `r10-final` logs |
| Azure self-test failures | 0 | 0 | All 50 task logs: `self-test cand: 13 ok, 0 bad, exit=0` and the same for champ (50/50) |
| Azure infrastructure losses | - | 3 jobs LOST, 1 build abandoned | EVENTS 22:18 (Cobalt node DiskFull from the standalone Dockerfile build, ~40 node-min lost), 22:31 (3 jobs LOST, 2 resubmitted); standalone build not retried on Arm |
| Losses found only on the bench (reverts) | 3 (ocaml-002 GC −3.0% Zen 5 1T; ocaml-005a limit 64 −3.1% Zen 3; ocaml-005b limit 96, Zen 3 +0.4% can't reach +1%) | 4 (ox-004 Cobalt −27.9%; ox-007 Cobalt −27.6%; ox-010 Cobalt −0.4%; ox-019 merge Zen 3 4T −1.2%) | LEDGER r10-ocaml-002/005a/005b, r10-ox-004/007/010/019; EVENTS 20:31, 21:12, 20:58, 21:25, 21:38, 23:20 |
| Of those, at the Cobalt (Arm) gate | 0 | 2 (ox-004, ox-007; both rebuilt x86-only as ox-008/ox-009 and kept) | EVENTS 20:58, 21:12 |
| Keeps | 1 (ocaml-004) | 9 into champion incl. 1 merge (ox-003, 006, 008, 009, 011, 014, 017, 021; ox-016 kept alone, lost when merged) | STATUS run 10 morning report "Keeps and rejects by kind" |
| Decided experiments | 6 | 16 | same |
| Faults found after the run | 1 (README) | 2 (README substance; Dockerfile rule) | `r10-final/COLD-READ.md`: two substance points (Cobalt two-run contradiction, unexplained +163%); HARNESS-BACKLOG item 39(e): standalone Dockerfile downloads a prebuilt `opam` binary, which CONTRIBUTING forbids (commit 74d2282, workshop) |

Faithfulness checks: every submit EVENTS line records a diff read for "one OR per composite"
(e.g. 20:12, 20:25, 21:00); over-20% gains re-read line by line (20:44, 21:25, 23:32). No
faithfulness defect was recorded.

**Run 9 ports (C++, Rust, Zig), same stages, brief.** Local gate was not applied to ports in run 9
("Chris: nothing dropped on local results", EVENTS 11T07:07), so losers went to the bench.
Bench-only losses: r9-cpp-wheel (Zen 3 −2.8%), r9-zig-base-wide (Zen 5 −8.9%), r9-zig-evex512
(flat), r9-rust-base-dense (flat), C++ wheel IDEAS 12 re-decided to revert (LEDGER r9-* rows).
Harness slips: two port submits refused (cand = champ), one reverted edit caught before push, one
worktree clash (RETRO run 9). Compile errors and self-test failures: not recorded. One real
correctness bug is on record for the ports, one run earlier (`ap-20261011T0100Z`): the C++ wheel
segfaulted under clang (undefined behaviour: `aligned(8)` ignored on a `may_alias` alias), found
only by switching compiler and fixed by p-cpp-wheel-ub (EVENTS 11T01:28, 11T02:33; LEDGER
p-cpp-wheel-ub). Same run: p-cpp-base-clang −62.6% on the Zen 5 screen (suspected de-vectorised loop).

## 2. Tooling: build times (run 10)

| What | Time | Source |
|---|---:|---|
| OxCaml 5.2.0+ox switch, local container (4 vCPU Xeon) | 1,183 s | OXCAML-NOTES "Build" |
| Switch build, Zen 5 node (16 vCPU) / whole toolchain image | 347 s / 561 s | `ox-000-toolchain` log; LEDGER r10-ox-000 |
| Switch build, Cobalt 100 (4 vCPU) / whole image | 604 s / 775 s | same |
| Image size; load on a node | 4.8 GB (1.2 GB zstd); ~50 s | EVENTS 19:51; STATUS run 10 |
| Plan's prediction for the switch | 30-60 min amd64, 60-120 min arm64 | LEDGER r10-ox-000 |
| Standalone Dockerfile (switch built inside the solution image), Zen 5 | 458 s | `ox-standalone-check` log; EVENTS 21:51 |
| Same on Cobalt | failed (disk full), not retried | EVENTS 22:18 |
| Per-task Docker build of a candidate on a node (logged from ox-012 on, commit c174090) | 2-114 s (median ~4 s; 44-114 s when layers weren't cached) | `build cand seconds:` in ox-012..ox-021 logs |
| Controls build per task | 0-67 s | `build ctx seconds:` same logs |
| Final scoreboard champion build | 43-137 s | `r10-final` logs |
| Single-file compile, OCaml 5.2 flambda / OxCaml (measured in run 11, same source) | 0.26 s / 0.46 s; type-check 0.03 s / 0.08 s | `fai-m1-tokens-build` README (run 11) |

Per-cycle wall clock (from EVENTS): 23 "Tick" and 14 "wakeup" commits in run 10. Agent start to
local verdict: 4-7 min (ox-013 21:41→21:48, ox-015 21:51→21:57, ocaml-007 23:09→23:13). Agent
start to Azure submit: 2-12 min (ocaml-004 20:16→20:21, ox-008 20:58→21:04, ox-021 23:09→23:11).
Agent start to bench decision: 23-42 min (ox-021 23 min, ox-009 26, ox-008 27, ox-004 42,
ocaml-004 42). Per-candidate wall clock as a field: not recorded. fai-m1 notes: "run 10's cycles
were slower because of the Docker and opam builds, not the compiler."

## 3. Agent effort

**Run 10 tokens.** The morning report's "main session: 1,030 calls, 148.4M" is the **main session
plus background-agent transcripts combined**. `tokens-climber.json` at the morning-report commit
(388e91d) gives main 258 + agents 772 = 1,030 calls and 82.1M + 66.3M = 148.4M; reads 81.5M +
64.3M = 145.8M; output 184k + 10k = 194k. The report's "24 agents ~2.3M" is the agents'
self-reported usage lines (lower bound, cache reads counted differently).

| Run 10 (22 decided experiments) | Model calls | Tokens | Per decided exp. | Source |
|---|---:|---:|---:|---|
| Main session (at report, 388e91d) | 258 | 82.1M (81.5M read, 0.45M write, 184k out, 583 fresh) | 11.7 calls, 3.7M | tokens-climber.json @388e91d |
| Background agents (transcripts) | 772 | 66.3M (64.3M read, 2.0M write, 9.8k out) | 35.1 calls, 3.0M | same |
| Both | 1,030 | 148.4M | 46.8 calls, 6.7M | STATUS run 10 "Tokens" |
| Final file (after late ticks) | 265 / 782 | 86.1M / 67.2M | - | tokens-climber.json (HEAD) |
| Agents, self-reported | 24 agents | ~2.3M | ~0.1M | STATUS run 10 |

Caveats: agent-transcript output (9.8k tokens over 772 calls) looks under-counted; "calls" are
model calls, not tool calls. **Per-agent tokens and tool calls for run 10: not recorded** (no
EVENTS, ledger or README figure; run 11 is the first to record them, e.g. fai-m1 89k tokens / 28
tool calls). EVENTS name 22 experiment agents (ox-001/002/004/005/007/008/009/010/011/012/013/
015/016/017/018/020/021, ocaml-001/003/004/006/007) plus the cold-read agent; the report says 24.

**Run 9** (25 decided + 2 scoreboards): main 244 calls / 100.2M, agents 478 calls / 39.4M at
report time, ~5.6M per experiment (4.0M main, 1.6M agents) (STATUS run 9 "Tokens"); file now
main 260 / 104.7M, agents 478 / 39.4M. Not cleared before the run (~0.4M cache read per call),
so its main-session figure is not comparable with run 10's (RETRO run 9). Per language: decided
C++ 4, Rust 5, Zig 6; tokens per language not recorded.

**Time to a first passing self-test.**

| Line | Agent start → local PRIMES_TEST=1 passes | First Azure self-test | Source |
|---|---|---|---|
| Plain OCaml base (ocaml-001) | 19:36 → accepted 20:00 (24 min, 2 ticks) | ocaml-002 task, results 20:18 | EVENTS 19:36, 20:00, 20:18 |
| OxCaml base (ox-002/003) | local switch first: ox-001 19:36 → 20:07 (1,183 s build); port agent 20:00 → both rebuilt and passing 20:12; 36 min from run start | ox-002 Zen 5 results 20:31 | EVENTS 20:07, 20:12, 20:31 |
| Rust wheel port | 07:18 → 07:31 (13 min) | phase B, 08:58 ("self-test 9 ok") | EVENTS 10T07:18, 10T07:31, 10T08:58 |
| Rust base port | 07:31 → 07:46 (15 min) | 09:21 | EVENTS 10T07:31, 10T07:46 |
| C++ base / wheel ports | 07:18 → 07:34 (16 min) / 07:47 (29 min, incl. tuning; also 5,396-size sweep) | 08:58 / 09:10 | EVENTS 10T07:18-07:47 |
| Zig base and wheel (z01) | agent start not recorded; running 12:05 on 9 Oct | not recorded | EVENTS 09T12:05 |

## 4. What an agent had to read; wrong docs; toolchain surprises (run 10)

| Item | Record |
|---|---|
| Read to find intrinsics | OxCaml test suite `oxcaml/tests/simd/amd64/builtins.ml` (builtin names), `stub_builtins.c` (link stubs); `backend/arm64/arch.ml` at tag 5.2.0minus-39 (unaligned access) (OXCAML-NOTES; EVENTS 22:32) |
| Docs gap | OxCaml docs: "NEON and AVX512 is coming soon"; no AVX-512 intrinsics in 5.2.0+ox; workshop later found 512-bit backend PRs in main but intrinsics PR closed unmerged (HARNESS-BACKLOG 40) |
| Avoided dune | `ocaml_simd` wraps the intrinsics but needs dune; externals declared by hand for a single-file build (OXCAML-NOTES 2a) |
| Network / opam | Workshop and climber networks blocked `opam.ocaml.org` (allowlisted before the run, BACKLOG 36); container proxy refused GitHub archive tarballs (403): tags cloned, tarballs rebuilt with `git archive`, checksums matched (OXCAML-NOTES "Build") |
| Plan out of date | Plan said 30+ min to build; took 6-10 min. Repo also carried 5.4.0+ox; plan named 5.2.0+ox (EVENTS 19:36, 19:51) |
| AVX2 by default | Compiler enables AVX2/BMI2/FMA when its build CPU has them; a hosted image would break the SSE4 Celeron (EVENTS 20:07 warn) |
| Language-level surprises | `int#` keeps 63-bit wrap (slowest); `Bytes.get_int64_le` bounds-checks (35 vs 19 instr); safepoint poll in every loop; `Domain.spawn` alerts and `portable` modes (OXCAML-NOTES 2b-2d); 16-bit primitive returns a tagged int, int32 constants not folded (ox-013, EVENTS 21:48) |
| Arm store barrier | OCaml 5 emits `ldr; dmb ishld; str` before 64-bit stores on Arm; found from compiled assembly (ox-018, EVENTS 22:55). RETRO: "two guesses at the Arm loop cost an hour before the assembly showed the store barrier in minutes" |
| Rule miss | Standalone Dockerfile fetches a prebuilt `opam` binary (CONTRIBUTING forbids); found in the workshop after the run (BACKLOG 39(e)) |
| Harness | Silent `hc-pool.sh submit` failure in a loop; diag runs needed a filter hack (HARNESS-BACKLOG run 10 notes) |

Docs consulted per agent (a list of pages or files read): not recorded.
