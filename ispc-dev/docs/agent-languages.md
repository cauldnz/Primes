# Do agent-specific programming languages help?

Run 11, 17 October 2026. One climb of the Primes drag-race base sieve in Fai, measured against
the same design in plain OCaml, OxCaml, Rust and ISPC on the same harness. It is one data point,
not a study.

## Terms

The [Primes drag race](https://github.com/PlummersSoftwareLLC/Primes) counts how many times a
program can sieve the primes below one million in five seconds. Each sieve is a pass. In the
"base" category every composite number must get its own marking operation, and the sieve must
start afresh each pass. The terms used below:
- **1T and 4T:** runs on one thread and on four threads; the leaderboard ranks passes per
  second per thread.
- **Climb:** a series of experiments by an AI agent (Claude Code). The climb keeps a change only
  if it beats the current best build, the champion, on Azure. Run 11 is the eleventh such climb
  in this repository.
- **Controls:** other entries run in the same rounds as the candidate:
  - our plain OCaml base (run 10);
  - mike-barber's Rust entry, the fastest faithful Rust base;
  - our ISPC base (ISPC is Intel's SPMD compiler).

  OxCaml, Jane Street's fork of OCaml, was climbed in run 10.
- **Dense and sparse:** small factors are marked through a repeating bit pattern, and large ones
  one multiple at a time.
- **Kernel:** the set of inner marking loops.
- **Names:** `fai-NNN` is one experiment; hex strings such as 84cc3eb are git commits; `hc/...`
  are branches.
- **Chris:** the repository's owner (`cauldnz`), who set the plan.

## The question

[Fai](https://github.com/Krzysztof-Cieslak/fai) is a small, strict, pure functional language in
the ML and F# family. It compiles ahead of time with Cranelift and is built for AI agents to
write. Its author makes four claims for it. This run took each claim as a hypothesis and
measured it against the general-purpose languages we had already climbed with the same design:
- **Correctness:** types, effects and contracts catch agent mistakes early.
- **Fast tooling:** quicker edit-check-test cycles.
- **Speed and memory:** fast generated code. Memory is managed by Perceus-style reference
  counting, the scheme from the Koka language that updates a value in place when it has a
  single owner.
- **Token efficiency:** ML-family source costs an agent fewer tokens.

The climber was Claude Code, with the same Claude model and harness as run 10 (plain OCaml and
OxCaml, 12 October) and run 9 (Rust, Zig and C++ ports, 11 October). Experiments ran as
background agents. Each passed a local gate, then ran on Azure Spot nodes:
- **Zen 5:** AMD EPYC 9V45.
- **Zen 3:** AMD EPYC 7763.
- **Cobalt 100:** Arm Neoverse N2.

Each measurement took six interleaved rounds, with the champion and three controls in every
round. We counted source tokens with one tokeniser, `tiktoken` 0.14.0 with `o200k_base`.

## Summary

| Claim | Verdict | Strength of evidence |
|---|---|---|
| 1. Types, effects and contracts catch agent mistakes early | Not supported in this run: almost no logic error reached them | Weak (few real mistakes to catch) |
| 2. Fast tooling | Fast in absolute terms, but slower than OCaml's compiler | Moderate |
| 3a. Fast generated code | Not supported on x86: a third of plain OCaml at 1T, a tenth per thread at 4T; ahead of OCaml on Arm at 1T | Strong for this program |
| 3b. Memory management (reuse, in place) | Supported: every update in place, 11MB peak | Strong |
| 4. Token efficiency | Not supported on source size or on agent tokens | Moderate on size; weak on agent tokens |

## The scoreboard

The final run had all five programs in the same six rounds on each machine, 17 October,
02:45-03:00 UTC (`results/hc/r11-final/`). Figures are passes in 5s.

| | Zen 5 1T | Zen 5 4T | Zen 3 1T | Zen 3 4T | Cobalt 1T | Cobalt 4T |
|---|---:|---:|---:|---:|---:|---:|
| Fai, final-run build (e80bf39) | 10.2k | 12.9k | 6.0k | 6.3k | 6.2k | 8.2k |
| Fai, plain loop (Phase 0, 1ce921d) | 2.0k | 7.4k | 0.9k | 3.6k | 1.2k | 4.7k |
| plain OCaml, same design | 32.9k | 120.6k | 17.2k | 65.9k | 3.4k | 13.0k |
| mike-barber Rust | 126.2k | 469.9k | 53.5k | 211.0k | 42.9k | 171.4k |
| our ISPC base | 139.0k | 517.7k | 56.8k | 224.4k | 42.0k | 168.1k |

At one thread the final-run build made 5.2, 6.5 and 5.3 times the passes of the Phase 0 loop on
Zen 5, Zen 3 and Cobalt (paired by round). That took Fai from a sixteenth (Zen 5) and a
nineteenth (Zen 3) of plain OCaml to about a third. On Cobalt it beat plain OCaml by 1.8 times, because OCaml pays an Arm store barrier
there. With threads, Fai stays far behind: about a tenth of OCaml per thread on Zen.

After the final run the climb kept one more Fai-specific change (fai-014). It masks each stored
word with a local `m = 0xFFFFFFFF`. The mask changes no value, since words hold 32 bits, but it
lets Fai's range analysis prove each word fits and drop an overflow check. Against e80bf39 in
the same rounds it gained +5.5% at 1T on Zen 5, +6.6% on Zen 3 and +21.6% on Cobalt, with 4T
unchanged. The champion, 84cc3eb, ran:

| 84cc3eb (fai-014 task) | Zen 5 | Zen 3 | Cobalt |
|---|---:|---:|---:|
| 1T | 10.8k | 6.3k | 7.6k |
| 4T | 13.0k | 6.4k | 8.3k |

Against plain OCaml from the same task's rounds, that is 0.33 and 0.37 of its passes at 1T on
Zen 5 and Zen 3, and 2.2 times on Cobalt.

## Claim 1: types, effects and contracts catch agent mistakes

**Prediction:** contracts and the effect checker would catch sieve bugs before any timing, and
fewer mistakes would reach the self-test or the bench than in run 10.

**What happened.** Every real mistake the agents logged in Fai (cycle tables in each experiment's
record):

| Stage | Real mistakes caught | What they were |
|---|---:|---|
| Self-review, before any tool ran | 4 | a wrong period formula, a wrong slot in an example, a nonsense example, a figure in a README |
| Name, type and effect checking (`fai check`, build) | 4 | a module not visible across files, an unqualified effect name, a wrong method name, an effect declared but not used |
| Contracts (`example`, `forall`) at `fai check` or `fai test` | 0 | (one planted off-by-one in Phase 0 was caught in 0.19s) |
| Formatter | 8 | layout only |
| Self-test (`PRIMES_TEST=1`) | 0 | |
| Azure build or self-test | 0 | |
| Reverted after the bench (speed regressions or no gain) | 6 of 11 decided | fai-006, fai-008, fai-009, fai-010, fai-012, fai-013 |
| Found only by reading the generated code | 1 | a call on a loop's exit branch silently dropped the fast path (fai-008) |
| Not caught by anything | 1 | examples attached to the wrong function after code moved; they still passed (fai-011) |

Run 10 (plain OCaml and OxCaml) recorded no compile errors and no failed self-tests either. The
failures it did record were of the same kind as here:
- five candidates stopped at the local gate on speed (none in run 11);
- seven of 22 decided experiments reverted after the bench, two of them on Cobalt;
- two OxCaml toolchain errors.

**Verdict:** not supported, on weak evidence.
- **No sieve bugs to catch.** The agents wrote correct sieves first time in both languages.
- **The checker's catches.** Of the four slips Fai's checker caught, three would also fail to
  compile in OCaml. The fourth, an unused effect, has no OCaml equivalent.
- **The contracts.** They caught no logic error, because none of the kind they check was
  written. They make a reviewer's job easier: 46 properties, including one that checks every
  sieve bit against trial division up to 4,999. That is a review benefit, and this run didn't
  measure it.
- **The bench.** Six of 11 experiments reverted against seven of 22 in run 10. Both were speed
  results, which no checker could catch.

One hazard counts against the claim. An `example:` line attaches to the declaration above it,
whatever function it calls. When an agent inserted a function, the examples silently moved to
the wrong name and still passed.

## Claim 2: fast tooling

**Prediction:** Fai's check, test and build would be faster than OCaml's, so cycles would be
shorter.

| Command, on the container's Xeon (median of 3) | Seconds |
|---|---:|
| `fai check` (types, effects and the `example` contracts) | 0.22 |
| `fai test` (all contracts) | 0.23 |
| `fai build`, native, with the link | 0.42 |
| OCaml 5.2 flambda `ocamlopt`, same design, with the link | 0.26 |
| OCaml type-check only | 0.03 |
| OxCaml, with the link | 0.46 |

Edit-check-test cycles in Fai took 1-2s from save to a passing self-test. From an agent's first
edit to its first passing self-test:

| Experiment | Time |
|---|---|
| fai-003 | 36s |
| fai-004 | 12s |
| fai-005 (it added a second file) | 3.5 min |
| fai-006 | 7s |
| fai-008 | 17s |
| fai-011 | 51s |

From each run's start to its first passing base sieve:

| Run | Time |
|---|---|
| Fai, Phase 0 (including the install) | about 8 minutes |
| run 10 plain OCaml | 24 minutes |
| run 10 OxCaml | 36 minutes |

Run 10 was slower because it had to build the OxCaml compiler toolchain (347-1,183s).

**Verdict:** fast in absolute terms, slower than OCaml, on moderate evidence.
- **Speed.** Every Fai command is sub-second, and Fai installs from a release in one command
  (37-42s inside the bench's Dockerfile).
- **Against OCaml.** OCaml's compiler is faster on a file this size: 0.26s to build against
  0.42s, and 0.03s to type-check against 0.22s, though `fai check` also runs the examples.
- **Against run 10.** The time saved came from not building a compiler toolchain, a matter of
  distribution.
- **The daemon.** Fai can keep a compiler daemon running between commands, but with one started,
  `fai daemon status` reported 0 commands served.

## Claim 3: generated-code speed and memory management

**Prediction:** the same design within a factor of two of plain OCaml, with every array update
in place through Perceus reuse.

The kept experiments, largest effect first:

| Experiment | What it did | Gain |
|---|---|---|
| fai-005 | moved the one-thread program out of concurrent mode | +187% to +273% at 1T |
| fai-003 | ported the OCaml design | +65% to +69% |
| fai-014 | the range-analysis mask | +5.5% to +21.6% at 1T |
| fai-011 | a kernel per program | +3% to +11% at 1T, +5% at 4T |

The first measurement was 16 times below plain OCaml at 1T on Zen 5 and 19 times on Zen 3. In
Phase 0 the same loop written in OCaml ran 2.1 times faster than the plain Fai loop on the
container (`results/hc/fai-000-feasibility/`). Porting the OCaml design gave +68%. The
compiler's concurrent mode then turned out to cost more than the design gap:
- **Concurrent mode.** A `Concurrency` effect anywhere in `main` switches the whole program to
  concurrent mode, and then every array read and write is a runtime call. Moving the one-thread
  run into a second program without `Concurrency` made it 3.1 times faster on Zen 5, 3.7 times
  on Zen 3 and 2.9 times on Cobalt (fai-005). The docs don't mention it. The compiler's design
  log calls the fix future work.
- **Threads.** There is no supported route around it for threads: hiding `Concurrency` from the
  compiler would be a data race (fai-007). The multi-thread runs stay in the slower mode, where
  per-thread speed on Zen is about a third of the one-thread run.
- **Two modes.** The one-thread program (inline array access) and the threaded one (runtime
  calls) wanted opposite changes. Unrolling the sparse loop helped the first and hurt the
  second, and building the first pass by appending did the opposite. A kernel per program won
  on every machine (fai-011).
- **Per-mark cost.** Inline access still costs 26-41 instructions per mark, depending on how
  the fast path is counted (fai-008 and fai-014 disassembly). Fai stores integers tagged, so
  each store retags the value and each access checks bounds. The plain OCaml entry builds with
  `-unsafe`, so it has no bounds checks.

Memory management did what the author says.
- **In place.** gdb on every allocation site showed one sieve and one scratch array per pass,
  with no copies and no growth, in both programs.
- **Peak memory.** Peak RSS was 11.2MB for both Fai programs. OCaml's one process peaked at
  194MB, mostly from the GC setting it uses for its multi-thread (OCaml "domain") runs.

**Verdict:** speed not supported on x86 and ahead of OCaml on Arm at one thread; memory
management supported. Both rest on strong evidence for this program.
- **Speed.** On Zen, Fai reaches about a third of plain OCaml at one thread and a tenth per
  thread with four. On Cobalt it beats plain OCaml at one thread, because OCaml pays a memory
  barrier on every 64-bit store there.
- **Memory.** Reference counting with reuse kept every update in place without the agent doing
  anything special. The one rule it had to learn was to keep the array uniquely owned.

## Claim 4: token efficiency

**Prediction:** the same sieve in fewer tokens than OCaml, Rust or ISPC, and fewer agent tokens
per experiment than run 10.

| Source, o200k tokens | With comments | Without comments |
|---|---:|---:|
| Fai, plain loop (Phase 0), no contracts | 2,595 | 2,067 |
| Fai, OCaml design (fai-009), no contracts | 4,772 | 3,487 |
| Fai, OCaml design, with contracts | 5,372 | 4,087 |
| Fai, final-run build (two kernels, e80bf39), no contracts | 5,940 | 4,332 |
| Fai, final-run build, with contracts | 6,814 | 5,206 |
| plain OCaml (solution_4) | 4,229 | 3,056 |
| ISPC base (solution_2) | 7,620 | 5,436 |
| Rust, mike-barber, bit-extreme-hybrid slice (undercounts) | 4,069 | 2,788 |

84cc3eb adds three `let m` lines and a mask per store to e80bf39; it was not counted separately.

Agent effort, counted from Claude Code's transcripts with the same method as run 10:

| | Run 10 (plain OCaml and OxCaml) | Run 11 (Fai) |
|---|---:|---:|
| Decided Azure experiments | 22 | 11 |
| Measurements and findings (no Azure decision) | 7 | 7 |
| Main-session model calls | 258 | 335 |
| Main-session tokens (transcripts) | 82.1M | 84.4M |
| Main-session tokens per decided experiment | 3.7M | 7.7M |
| Background-agent tokens (transcripts) | 66.3M | 42.4M |
| Background-agent tokens per decided experiment | 3.0M | 3.9M |
| Background-agent tokens, each run's own usage line, total | about 2.3M (24 runs) | about 1.4M (12 runs; 82k-172k each) |

Notes on the token figures:
- **Two measures.** Transcript tokens include every cache read: the whole conversation is read
  back on each model call. An agent run's usage line counts far less, mostly new input and
  output. The verdict uses the transcript measure, the same one run 10 reported.
- **Window.** Run 11's figures run to 03:20 UTC and leave out Phase 0, which shared a session
  with other work. Main-session tokens are almost all cache reads (83.5M of 84.4M, with 224k
  output).
- **What the main session also did.** It also wrote this report, the run 10 reconstruction
  brief and the per-experiment records.

**Verdict:** not supported, on moderate evidence for source size and weak evidence for agent
tokens.
- **Source size.** For the same design, Fai is 13% larger than OCaml without its contracts and
  27% larger with them. The second program file, needed because of concurrent mode, costs 529
  tokens on its own. The final-run build, with a kernel per program, is 5,940 tokens without
  contracts: 40% more than OCaml's 4,229.
- **Agent tokens.** Per decided experiment, background agents used 3.9M transcript tokens
  against run 10's 3.0M, and the main session about twice as many (7.7M against 3.7M). Run 11
  had fewer, larger experiments, more measurement work and this report. One run can't separate
  the language from the work, and nothing here shows Fai saving tokens.

## Using Fai's own features

Chris asked mid-run that the climb also use features unique to Fai.

| Feature | What it did here |
|---|---|
| Perceus reference counting with in-place reuse | every update in place with no effort; 11MB peak |
| Effect rows that set the compile mode | dropping `Concurrency` from the one-thread program tripled its speed |
| Owned-loop specialisation | one reference-count check per loop, if the loop stays a single self-recursive function with no calls |
| Range analysis (`bounds.rs`) | a no-op mask bound to a local (`let m = 0xFFFFFFFF`) lets it prove each word fits, and the overflow check goes (fai-014) |
| `example` and `forall` contracts | 46 properties checked in a fifth of a second, including every sieve bit against trial division |
| `fai query caps` | shows from the effect rows that a binary is not in concurrent mode |
| `ProcessHost.Process` | starts processes without concurrent mode: 3.4 times the passes at 4T locally, but not used (Chris ruled out multi-process runs) |

A survey of the docs and compiler source (fai-015) looked for these features and found them
missing in 0.1.0:
- per-task or per-function concurrent mode;
- slices of `Array Int`;
- `requires` or `ensures` contracts that the optimiser uses;
- inline or specialise annotations;
- a writable byte or packed array.

Fai's design does reward code written for its optimiser. The rewards are large: 2.9 to 3.7
times from dropping `Concurrency` and up to 22% from one mask. Agents found them only by
reading the compiler's source.

## What an agent had to read

- **Agent docs.** `llms.txt` and `docs/` were enough to write a correct sieve first time in
  Phase 0. Three of the later agent runs (the OCaml port fai-003, fai-006 and fai-011) read no Fai
  docs or compiler source at all; the existing source and our notes were enough.
- **Where performance lived.** Agents answered every performance question by reading the
  compiler's source and its design log (`docs/MEMORY.md`):
  - the concurrency switch (`emit.rs`, `entry.rs`);
  - the owned-loop plan (`array_loop.rs`);
  - the range analysis behind the overflow check (`bounds.rs`).

  Each answer took an agent 3-8 minutes.
- **Where the docs were wrong or silent:**
  - `unsafeGet` and `unsafeSet` still check bounds;
  - `Clock.now` is wall-clock milliseconds;
  - shift counts wrap mod 64;
  - a single-file build needs a `fai.toml` to see sibling files;
  - the launcher ignores `SSL_CERT_FILE`;
  - the process API works without `Concurrency`, which shows only in a sample.

## What this run can and can't say

It is one climb of one small, array-bound program by one model. A sieve is close to the worst
case for a pure language: one mutable array, hammered. Claims 1 and 4 would need a larger
program with more ways to go wrong. The evidence that holds most firmly is the performance
model:
- `Concurrency` changes how every array access compiles;
- an array loop must stay one self-recursive function with no calls to keep its fast path;
- Fai tags its integers, so a full 64-bit value boxes on every store, which is why the sieve
  keeps 32 bits per word.

An agent-facing language would do well to put that model in its agent docs.

## Sources

- **Experiments.** Ledger rows `r11-fai-*` in `results/hc/LEDGER.md`, folders
  `results/hc/fai-*` and branches `hc/fai-*`.
- **Run 10 comparison:** `results/hc/fai-r10-evidence/README.md`.
- **Lesson candidates:** `results/hc/fai-lessons.md`.
- **Notes for the Fai author:** `drafts/fai-notes.md` (not sent).
