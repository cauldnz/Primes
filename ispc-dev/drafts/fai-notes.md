# Notes for the Fai author (draft, not sent)

From run 11, a research climb of the Primes drag-race base sieve in Fai 0.1.0 (release commit
ca5b9c8), on x86-64 Linux. Not filed upstream; Chris decides whether and how to share.
Evidence and repros: `results/hc/fai-000-feasibility/README.md` on `ispc-dev`.

Performance:
- A store into `Array Int` of a value outside 63 bits boxes it. A sieve with 64 bits per element
  ran 429 passes in 5 s against 1,097 with 32 bits per element.
- `Array.unsafeGet` / `unsafeSet` compile to out-of-line runtime calls with a bounds check, a
  reference-count check and a drop of the old element on every store. The same loop in plain
  OCaml is 2.1 times faster; an inline fast path for a unique `Array Int` would likely close
  most of that.

Docs:
- `llms.txt` (line 1457) says the `unsafe*` array functions skip the bounds check; they check
  and abort (exit 134).
- `Clock.now` is wall-clock milliseconds (`SystemTime`); that isn't documented, and there is no
  monotonic clock for timing.
- `Int.shiftLeft` / `shiftRight` take the count mod 64 (`shiftLeft 1 64 = 1`); undocumented.

Tooling:
- No way to set the process exit status from `main` (we used a `foreign "exit"` capability).
- An `FAI6001` failure for `example: a = b` reports the line but not the two values.
- `fai build --release` is accepted but has no effect in 0.1.0.
- Installing behind a TLS-intercepting proxy: the launcher's downloader uses built-in roots and
  ignores `SSL_CERT_FILE`; the documented loopback mirror (`FAI_RELEASE_BASE_URL`) works around
  it, but honouring the system or `SSL_CERT_FILE` trust store would make the one-line installer
  work in such environments.
