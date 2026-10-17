# Run plan: Fai (run 11, agreed with Chris, 2026-10-17 10:35 AEST)

Read this after `AUTOPILOT.md`. It sets this run's priorities, limits and end steps. Everything
else in the brief, the runbook and `HILL-CLIMB.md` still applies, including the "Never without
Chris" list. The previous plan (run 10, OxCaml) is in git history; its results are in the run 10
morning report in `STATUS.md`.

This is a research climb in Fai (https://github.com/Krzysztof-Cieslak/fai), a small, strict,
pure functional language in the ML / F# family with a native compiler, built for AI agents.
**No upstream PR, ever.** The work lives in `PrimeFai/solution_1` on `hc/fai-*` branches only.

## Limits

- Time box: 5 hours from the session start. Stop starting experiments at 4h15; the final
  scoreboard and shutdown take the last 45 minutes.
- Azure: NZ$15 for the run, Spot only, take every pool down when done and confirm nothing is
  left running (`az batch pool list`). Check each log's CPU model line before counting it.
- The ISPC and OCaml entries are frozen; they appear only as controls.
- Write a "Run ... started" event first thing (`st.py`).

## Step 0: Azure access

Check `az account show` and a harmless read of the Batch account before anything else. If the
cached login or the service principal secret fails, don't work around it: tell Chris exactly
what is needed, carry on with Phase 0 only (it runs in the container), and stop before Phase 1.
Local timings in Phase 0 screen only; nothing is decided on them.

Knowledge base: if the agentic-hill-climber knowledge base (knowledge/, Foundry IQ) is up and
its endpoint is known, query it before planning and cite card ids in ledger entries; if not,
say so and carry on.

## Phase 0 (90 minutes at most): feasibility

- Install Fai from its prebuilt release; record version and commit. Read `llms.txt` and `docs/`
  before writing code.
- Answer, with evidence: mutable arrays or byte buffers and whether updates happen in place;
  bitwise operations and shifts on 64-bit integers; loops or guaranteed tail calls; threads or
  structured concurrency usable for one sieve per thread; a monotonic clock; stdout; bounds
  checks and any unchecked access; SIMD (likely none); arm64 support.
- Write a plain faithful base sieve in `PrimeFai/solution_1` on `hc/fai-*` branches: one bit per
  odd number, the contest output format, a `PRIMES_TEST` self-test, label `cauldnz-fai-base`,
  tags `algorithm=base,faithful=yes,bits=1`. Use Fai's `example` and `forall` contracts for the
  sieve's properties.
- If Fai can't express an in-place sieve at a sane speed (about 100 times slower than our plain
  OCaml base), stop, record why, and report. That is a result.

## Session boundary (Chris, 2026-10-17)

Phase 0 ran in a session shared with run 10 and the F2 measurement, so its main-session tokens
are not comparable with run 10's (which began after a clear). At the Phase 0 / Phase 1 boundary,
once the Phase 0 agent has reported and everything is pushed, Chris clears the session and a new
one resumes run 11 from git (`STATUS.md` "Run 11 handover", `status.json`, the ledger). The
secret can't go into the environment's variables, so the new session checks Azure first and
asks Chris to paste the secret if the cached login has gone.
In the report, claim 4 leads with background-agent tokens and source size; main-session tokens
are split into new input plus output against cache reads, with Phase 0's marked as shared.

## Phase 1: bench

A bench kind for Fai in `hc-pool.sh` on the pattern of the `ocaml` kind (the Dockerfile installs
Fai from its release; a cached image per architecture). Controls: our plain OCaml base
(`hc/ocaml-final`, `PrimeOCaml/solution_4`), mike-barber's Rust, our ISPC base
(`hc/ispc-landing-4`, `PrimeISPC/solution_2`). Per thread at 1T and 4T on Zen 5 and Zen 3,
Cobalt at 1T.

## Phase 2: climb

Climb the Fai base under the keep rule (`HILL-CLIMB.md`, "Acceptance rule"). Port the base
design from the OCaml line first (kind `borrowed`, name the source), then Fai-specific ideas.

## The author's claims, as hypotheses

Fai's author claims four things. Each gets a prediction and the evidence for or against:

1. **Correctness**: the types, effects and contracts catch agent mistakes early. Measure:
   mistakes caught by `fai check`, `fai test` or contracts before timing, against those that
   reached the bench or the self-test; compare with run 10's OCaml and OxCaml lines.
2. **Fast tooling**: quicker iteration. Measure: wall-clock time per edit-check-test cycle and
   per build, against OCaml and OxCaml in run 10.
3. **Generated-code speed and memory management** (Perceus-style reference counting with reuse).
   Measure: the scoreboard against plain OCaml and Rust with the same design, and whether the
   sieve's array updates actually happen in place (evidence: a profile, allocation counts or the
   generated code).
4. **Token efficiency of ML-family languages.** Measure: tokens per experiment against run 10,
   and the size of the same base sieve's source in tokens across Fai, OCaml (solution_4), Rust
   and ISPC, counted with one tokenizer (named in the report).

Say plainly where a claim isn't supported, and where one run is too small to tell.

## Also record, for the knowledge base and the talk

- Tokens per experiment, main session and background agents separately.
- Lesson candidates as they happen (prediction misses, protocol surprises, anything
  Fai-specific), one line each with the experiment id, in `results/hc/fai-lessons.md`.
- Anything worth telling Krzysztof (bugs found, performance gaps with a minimal repro), drafted
  in `drafts/fai-notes.md`. Don't file issues upstream or contact anyone.

## Outputs (Chris, 2026-10-17)

1. **The normal dashboard.** Every experiment, verdict, decision and event goes into
   `status.json`, the ledger and `results/hc/EVENTS.jsonl` as in earlier runs, so the climb
   shows on the status page like any other. Fai experiments use ids `fai-NNN`.
2. **A separate report: "Do agent-specific programming languages help?"** Written at the end
   as `docs/agent-languages.md` and published as a page, built around the author's claims as
   hypotheses, with Fai against the general-purpose languages we have climbed with the same
   design and harness (plain OCaml and OxCaml in run 10; Rust, Zig and C++ ports in run 9 where
   the record allows). Evidence per claim, gathered during the run:
   - correctness: mistakes caught per stage (type checker, effects, contracts, `fai test`,
     self-test, bench) from the cycle log, against the same stages in run 10, reconstructed
     from its ledger and agent reports (local-gate rejects, self-test failures, Cobalt
     losses);
   - tooling: wall-clock per edit-check-test cycle and per native build, against OCaml and
     OxCaml compile times measured on the same container;
   - speed and memory: the scoreboard (or local screens while Azure is blocked) and peak RSS;
   - agent effort: tokens and tool calls per decided experiment and to a first passing self-test,
     against run 10;
   - what an agent had to read: llms.txt and docs consulted, and where they were enough or
     wrong.
   Each claim ends with a verdict (supported, not supported, not tested) and how strong the
   evidence is. A single climb is one data point; the report says so.

## Morning report

Whether Fai could run the sieve and how long set-up took, the scoreboard, the four claims with
evidence, keeps and rejects by kind, tokens per experiment (main session and background agents
separately), and the lesson candidates. Step 0 note: Azure failed at the start (expired
service-principal secret) and was restored mid-Phase 0 with a new secret from Chris.
