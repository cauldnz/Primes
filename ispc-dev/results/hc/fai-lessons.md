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
