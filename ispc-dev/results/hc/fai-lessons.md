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
