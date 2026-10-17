# Run 11 (Fai) lesson candidates

One line each, with the experiment id, as they happen.

- fai-000: The Fai launcher's downloader carries its own certificate roots and ignores
  SSL_CERT_FILE, so `install.sh` fails behind a TLS-intercepting proxy; the documented loopback
  mirror (FAI_RELEASE_BASE_URL) worked with release assets fetched by curl.
- run: The service-principal secret had expired at the start (AADSTS7000222); check it in Step 0
  of every run, as this plan does.
- fai-000: In Fai a mutable-looking array update is in place only while the array has one
  reference; the agent proved it with gdb on the runtime's copy path (0 copies in the sieve,
  1,000 in a shared control). Timing alone would have shown it, but not why.
- fai-000: Fai's `Int` is tagged 63-bit inside arrays: packing 64 bits per element boxed every
  store and cut passes 2.5 times (1,097 to 429); 32 bits per element was fastest. The design
  rule from OCaml (fill the word) is wrong here; check the boxing boundary first.
- fai-000: No type, effect or contract error in 15 cycles of writing the sieve: the agent wrote
  it right first time (first passing self-test after 4 cycles, 109 s). Contracts caught a
  planted off-by-one at `fai check` (0.19 s), before any build. Claim 1 evidence so far is the
  mutant, not real mistakes.
- fai-000: Every Fai command took 0.01-1.1 s (check 0.25 s, native build 0.6 s); OxCaml builds
  were 2-5 s and the bench image build minutes. Claim 2 looks supported on this container.
- fai-000: The plain Fai sieve is 20 times slower than our climbed OCaml base but only 2.1 times
  slower than the same loop in plain OCaml: most of the gap to solution_4 is design, not
  language. Phase 2 should port the OCaml design first, as planned.
- fai-001: `bits=1` holds for the logic (one bit per odd number), but 32 bits per 64-bit slot
  means about 2 bits of memory per candidate; say so in the report.
- fai-m1: On one 300-line file the compilers are all sub-second: Fai native build 0.42 s,
  `fai check` 0.22 s, OCaml 5.2 flambda 0.26 s (type-check 0.03 s), OxCaml 0.46 s. The fast
  tooling claim holds in absolute terms but Fai is not faster than OCaml here; run 10's slow
  cycles were Docker and opam, not the compiler. Compare like with like before crediting a
  language.
- fai-m1: `fai daemon status` showed 0 commands served after `fai build` with the daemon
  running; the build may bypass the daemon in 0.1.0.
- fai-003: Each Fai array access is a runtime call, so the dense-pattern design pays only while
  there are more than about 1.25 multiples per slot (p below about 25 with 32-bit slots); the
  dense limit fell from OCaml's 128 to 16. Limits tuned on native code don't carry over.
- fai-003: The OCaml design port took 10.5 min of agent time; first edit to first passing
  self-test 36 s; no mistake reached the type checker, contracts or self-test; two slips were
  caught in the agent's own review before any tool ran, two formatter fails. Claim 1 still
  rests on mutants, not real catches.
- fai-003: Passing a uniquely owned scratch array through a read-only loop and reusing it did
  not copy (gdb 0); Perceus restores the count before the next write.
- run: hc-pool.sh tally billed 5 days because its meter state was left from the previous run;
  a tally should reset state older than the run.
- fai-004: The compiler inlines `Array.push`'s fast path into the calling loop (growth goes
  through `fai_alloc_array` from compiled code), while get and set stay runtime calls. A gdb
  check on runtime copy sites alone misses push growth; log every `alloc_obj` caller instead.
- fai-004: Count runtime calls per pass before predicting a Fai gain: the push-built pass for 3
  saves about 2% of calls; the prediction of +5-15% assumed native-code costs.
- fai-005: The biggest Fai gain was not in the sieve: `Concurrency` in `main`'s effect row turns
  off the compiler's inline array fast path for the whole program (emit.rs `array_prim`), so
  every get and set became a runtime call. A 1T binary without `Concurrency` ran 3x faster with
  the same sieve code. Phase 0's "each mark is two runtime calls" was true only of the
  concurrent build; read the compiler before trusting a profile's explanation.
- fai-005: The prediction (+10-40%) missed by an order of magnitude upward, as run 10's misses
  did with SIMD: a mode switch in the compiler is invisible from the source and the docs.
- fai-005: A single-file `fai build` sees sibling modules only when a `fai.toml` exists;
  `fai check/fmt/test` take one path (use `.`); cross-module effects are named `Module.Effect`.
- fai-007: Fai's concurrent mode is a whole-program switch from `main`'s effect row; one trivial
  `Async.parallel` makes all array code about 4x slower, and nothing scopes it. Multi-thread
  per-thread speed in Fai 0.1.0 is capped by the compiler, not the sieve.
- fai-007: The agent answered a compiler question in 3 minutes by reading the compiler's own
  design log (`docs/MEMORY.md`) and source; `llms.txt` was silent. For agent-facing languages,
  the performance model belongs in the agent docs.
- fai-006: The dense-limit break-even depends on bits per slot: with 32-bit slots the best limit
  was 32, half of what OCaml's 64-bit words suggest; 64 lost 12%, 128 lost 30%.
- fai-006: Single 5-second runs on the container vary by about ±8%; finalists need 8 or more
  paired interleaved rounds, not 2-3 run screens.
- fai-008: A self-recursive Fai array loop loses its uniquely-owned specialisation if its body
  calls any other function, even only on the exit branch (`array_loop.rs` `Scan::walk`). It
  passed every check; only objdump and timing caught it.
- fai-008: Unrolling saves only loop overhead in Fai (30 to 26 instructions per mark); bounds,
  tag and retag costs stay on every access. A 1T gain came with a local 4T loss in concurrent
  mode (register pressure across runtime calls): gate both paths.
- fai-008: `/ 32` and `% 32` on Fai's signed Int add sign fix-ups; use shifts.
- r10-evidence: Run 10's morning report gave "main session 1,030 calls, 148.4M tokens"; that
  figure was the main session and the agent transcripts together (258 + 772 calls; 82.1M +
  66.3M). Label token totals by source when writing them, and record per-agent usage, as run 11
  does.
- fai-005: On Azure the 1T split gave 3.1x (Zen 5), 3.7x (Zen 3) and 2.9x (Cobalt); Fai's 1T on
  Cobalt (5.6k) now beats plain OCaml (3.4k), which pays the Arm store barrier.
- fai-006: The same dense limit (32) gained 8.5% on Zen 5 and lost 1.9% on Zen 3 at 1T: the
  pattern-OR versus per-mark break-even is chip-specific; the container screen (+5%) could not
  see it.
- fai-m2: Like for like, the Fai program is larger than the OCaml one: 4,772 o200k tokens
  without contracts (5,372 with) against 4,229. The plain-loop count from fai-m1 (2,945) had
  flattered Fai; compare designs, not files. Claim 4 is not supported on source size.
- fai-m2: Peak RSS 11.2 MB for both Fai binaries against 194 MB for OCaml's one process
  (multi-domain GC setting); gdb confirms every update in place. Claim 3's memory half holds.
- fai-m2: The 1T binary allocates small objects through an inline pool path that never calls
  `alloc_obj`; counting `alloc_obj` callers alone found 7 of 13 sieves. Break on every
  allocation site.
- fai-008/009: The inline 1T binary and the call-based threaded binary want opposite changes:
  unrolling helps 1T (+2-11%) and hurts 4T (−2.5%); the push-built pass for 3 helps 4T (+2%)
  and hurts 1T (−1.6%). In Fai the compile mode, not the chip, is the main axis for tuning.
- fai-004: A change kept on one base lost when merged onto a later keep; measure every merge.
