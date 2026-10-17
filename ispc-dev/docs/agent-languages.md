# Do agent-specific programming languages help?

Run 11, 17 October 2026. One climb of the Primes drag-race base sieve in Fai, measured against
the same design in plain OCaml, OxCaml, Rust and ISPC on the same harness. It is one data point,
not a study.

## The question

[Fai](https://github.com/Krzysztof-Cieslak/fai) is a small, strict, pure functional language in
the ML and F# family. It compiles ahead of time with Cranelift and is built for AI agents to
write. Its author makes four claims for it. This run took each claim as a hypothesis and
measured it against the general-purpose languages we had already climbed with the same design:
- **Correctness:** types, effects and contracts catch agent mistakes early.
- **Fast tooling:** quicker edit-check-test cycles.
- **Speed and memory:** fast generated code, with Perceus-style reference counting and reuse.
- **Token efficiency:** ML-family source costs an agent fewer tokens.

The climber was Claude Code, the same model and harness as run 10 (plain OCaml and OxCaml, 12
October) and run 9 (Rust, Zig and C++ ports, 11 October). Experiments ran as background agents.
Each one was gated locally, then measured on Azure Spot nodes:
- **Zen 5:** AMD EPYC 9V45.
- **Zen 3:** AMD EPYC 7763.
- **Cobalt 100:** Arm Neoverse N2.

Each measurement took six interleaved rounds, with the champion and three controls in every
round. Tokens were counted with one tokenizer, `tiktoken` 0.14.0 with `o200k_base`.

## Summary

| Claim | Verdict | Strength of evidence |
|---|---|---|
| 1. Contracts and types catch agent mistakes early | Not supported in this run: almost nothing reached them | Weak (few real mistakes to catch) |
| 2. Fast tooling | Supported in absolute terms; no faster than OCaml's compiler | Moderate |
| 3a. Fast generated code | Not supported: a third of plain OCaml's speed per thread on Zen | Strong for this program |
| 3b. Memory management (reuse, in place) | Supported: every update in place, 11 MB peak | Strong |
| 4. Token efficiency | Not supported on source size or on agent tokens | Moderate on size; weak on agent tokens |

<!-- FINAL-SCOREBOARD -->

## Claim 1: types, effects and contracts catch agent mistakes

**Prediction:** contracts and the effect checker would catch sieve bugs before any timing, and
fewer mistakes would reach the self-test or the bench than in run 10.

**What happened.** Every real mistake the agents logged in Fai (cycle tables in each experiment's
record):

| Stage | Real mistakes caught | What they were |
|---|---:|---|
| Self-review, before any tool ran | 4 | a wrong period formula, a wrong slot in an example, a nonsense example, a figure in a README |
| Name, type and effect checking (`fai check`, build) | 4 | a module not visible across files, an unqualified effect name, a wrong method name, an effect declared but not used |
| Contracts (`example`, `forall`) at `fai check` or `fai test` | 0 | (one planted off-by-one in Phase 0 was caught in 0.19 s) |
| Formatter | 7 | layout only |
| Self-test (`PRIMES_TEST=1`) | 0 | |
| Azure build or self-test | 0 | |
| Found only on the bench | 3 | fai-006, fai-008, fai-009: speed, not correctness |
| Found only by reading the generated code | 1 | a call on a loop's exit branch silently dropped the fast path (fai-008) |
| Not caught by anything | 1 | examples attached to the wrong function after code moved; they still passed (fai-011) |

Run 10 (plain OCaml and OxCaml) recorded no compile errors and no failed self-tests either. Its
agents' failures that left a trace were the same kind as here:
- five candidates stopped at the local gate on speed;
- seven reverts found only on the bench, two of them on Cobalt;
- two OxCaml toolchain errors.

**Verdict: not supported, on weak evidence.** The agents wrote correct sieves first time in both
languages. Fai's checker caught four slips that OCaml's compiler would also have caught. Its
contracts caught no real mistake, because there was none for them to catch. The contracts did
make the self-test redundant. They also make a reviewer's job easier: 46 properties, including
one that checks every sieve bit against trial division up to 4,999. That is a review benefit,
and this run didn't measure it.

One hazard counts against the claim. An `example:` line attaches to the declaration above it,
not to the function it calls. When an agent inserted a function, the examples silently moved
to the wrong name and still passed.

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

Edit-check-test cycles in Fai took 1-2 s from save to a passing self-test. From an agent's
first edit to its first passing self-test:

| Experiment | Time |
|---|---|
| fai-004 | 12 s |
| fai-006 | 7 s |
| fai-008 | 17 s |
| fai-003 | 36 s |
| fai-011 | 51 s |
| fai-005 (it added a second file) | 3.5 min |

Run 10's cycles were slower, but not because of the compiler:
- building the OxCaml toolchain took 347-1,183 s;
- each candidate's Docker build on a node took a median of about 4 s;
- its first plain OCaml base took 24 minutes from the run's start to a passing self-test, and
  OxCaml took 36.

**Verdict: supported in absolute terms, not against OCaml, on moderate evidence.** Every Fai
command is sub-second, and Fai installs from a release in one command (37-42 s inside the
bench's Dockerfile). But OCaml's own compiler is as fast on a file this size. The speed-up
over run 10 came from not building a compiler toolchain, which is about distribution, not
language design. `fai build` with the daemon running reported 0 commands served, so the daemon
may not have been used.

## Claim 3: generated-code speed and memory management

**Prediction:** the same design within a factor of two of plain OCaml, with every array update
in place through Perceus reuse.

<!-- SPEED-TABLE -->

The first measurement was 20 times below OCaml. Most of that gap was design: the plain Fai loop
was 2.1 times slower than the same loop in OCaml. Porting the OCaml design gave +68%. The rest
of the climb found that Fai's speed is set by its compiler's modes more than by the source:
- **The biggest step had nothing to do with the sieve.** A `Concurrency` effect anywhere in
  `main` switches the whole program to concurrent mode, and then every array read and write is
  a runtime call. Moving the one-thread run into a second program without `Concurrency` made it
  3.1 times faster on Zen 5, 3.7 times on Zen 3 and 2.9 times on Cobalt (fai-005). The docs
  don't mention it; the compiler's design log calls the fix future work.
- **No supported route around it for threads.** Hiding `Concurrency` from the compiler would be
  a data race (fai-007). The multi-thread runs therefore stay in the slower mode. On Zen
  their per-thread speed is about a third of the one-thread run.
- **The two modes want different code.** Unrolling the sparse loop helped the inline build and
  hurt the call-based one; building the first pass by appending did the opposite. Giving each
  program its own kernel was kept on every machine (fai-011).
- **Inline access still costs about 26 instructions per mark.** The per-mark cost is a bounds
  check, a tag test, an overflow-checked retag and a check before dropping the old element.
  OCaml with `-unsafe` needs a handful.

Memory management did what the author says. gdb on every allocation site showed one sieve and
one scratch per pass, no copies and no growth, in both programs. Peak RSS was 11.2 MB for both
Fai programs. OCaml's one process peaked at 194 MB, mostly from the GC setting it uses for its
multi-domain runs.

**Verdict: speed not supported, memory management supported, both on strong evidence for this
program.** On Zen, Fai reaches about a third of plain OCaml per thread at one thread, and less
with threads. On Cobalt it beats plain OCaml, which pays a memory barrier on every 64-bit store.
Reference counting with reuse kept every update in place without the agent doing anything
special. The one rule it had to learn was to keep the array uniquely owned.

## Claim 4: token efficiency

**Prediction:** the same sieve in fewer tokens than OCaml, Rust or ISPC, and fewer agent tokens
per experiment than run 10.

| Source, o200k tokens | With comments | Without comments |
|---|---:|---:|
| Fai, plain loop (Phase 0), no contracts | 2,595 | 2,067 |
| Fai, OCaml design (fai-009), no contracts | 4,772 | 3,487 |
| Fai, OCaml design, with contracts | 5,372 | 4,087 |
| plain OCaml (solution_4) | 4,229 | 3,056 |
| ISPC base (solution_2) | 7,620 | 5,436 |
| Rust, mike-barber, bit-extreme-hybrid slice (undercounts) | 4,069 | 2,788 |

<!-- TOKENS-TABLE -->

**Verdict: not supported, on moderate evidence for source size and weak evidence for agent
tokens.**
- **Source size.** For the same design, Fai is 13% larger than OCaml without its contracts and
  27% larger with them. The split into two programs, forced by the concurrency mode, added 529
  tokens.
- **Agent tokens.** Per decided experiment, agent tokens came out close to run 10's. The
  sessions differ in length and in the size of each experiment, so one run can't separate the
  language from the work.

## What an agent had to read

- **Agent docs.** `llms.txt` and `docs/` were enough to write a correct sieve first time in
  Phase 0. Later agents mostly needed only the existing source and our own notes.
- **Where performance lived.** Every performance question was answered by reading the compiler's
  source and its design log (`docs/MEMORY.md`), not `llms.txt`:
  - the concurrency switch (`emit.rs`, `entry.rs`);
  - the owned-loop plan (`array_loop.rs`);
  - the range analysis behind the overflow check (`bounds.rs`).

  Each answer took an agent 3-8 minutes.
- **Where the docs were wrong or silent:**
  - `unsafeGet` and `unsafeSet` still check bounds;
  - `Clock.now` is wall-clock milliseconds;
  - shift counts wrap mod 64;
  - a single-file build needs a `fai.toml` to see sibling files;
  - the launcher ignores `SSL_CERT_FILE`.

## What this run can and can't say

It is one climb of one small, array-bound program by one model. A sieve is close to the worst
case for a pure language: one mutable array, hammered. Claims 1 and 4 would need a larger
program with more ways to go wrong. The evidence that holds most firmly is the performance
model:
- `Concurrency` changes how every array access compiles;
- an array loop must stay one self-recursive function with no calls to keep its fast path;
- 64-bit words box.

An agent-facing language would do well to put that model in its agent docs.

## Sources

- **Experiments.** Ledger rows `r11-fai-*` in `results/hc/LEDGER.md`, folders
  `results/hc/fai-*`, and branches `hc/fai-*`.
- **Run 10 comparison:** `results/hc/fai-r10-evidence/README.md`.
- **Lesson candidates:** `results/hc/fai-lessons.md`.
- **Notes for the Fai author:** `drafts/fai-notes.md` (not sent).
