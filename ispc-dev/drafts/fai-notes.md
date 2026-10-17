# Notes for the Fai author (draft, not sent)

From run 11, a research climb of the Primes drag-race base sieve in Fai 0.1.0 (release commit
ca5b9c8), on x86-64 Linux. Not filed upstream; Chris decides whether and how to share.
Evidence and repros: `results/hc/fai-000-feasibility/README.md` on `ispc-dev`.

Performance:
- **Largest finding.** A `Concurrency` effect anywhere in `main`'s effect row switches the whole
  program to concurrent mode, and `array_prim` (`crates/fai-codegen/src/emit.rs`, about line 4182)
  then returns `None`: no inline `Array` get or set anywhere, even for arrays that never leave one
  task. The same read-OR-write sieve ran 3.0x the passes at one thread when built without
  `Concurrency` in `main` (5,458 against 1,813 in 5 s, container Xeon). Repro: one loop, built
  with and without `Concurrency` on `main`. A per-function mode, or an inline fast path with an
  atomic reference-count check, would fix it. Nothing in the docs mentions it.
- With inlining on, the unique-specialised `Array Int` loop still reloads the length every
  iteration, tag-checks the loaded slot, overflow-checks the retag (`seto`, cold `make_int`) and
  tag-checks before dropping the old element: 29 instructions per mark.
- The "`unsafeGet`/`unsafeSet` compile to out-of-line calls" note below is true only of the
  concurrent build.
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

Docs (from fai-005):
- `fai build file.fai` sees sibling modules only with a `fai.toml` present; not in `llms.txt` section 5.
- `fai check`, `fmt` and `test` take one path; a multi-file directory needs `.`.

Concurrency (from fai-007; evidence and repro in `results/hc/fai-007-inline-parallel/`):
- Repro: the same single-threaded `Array Int` loop runs 0.30 s with no `Concurrency` in `main`
  and 1.25 s when `main` also runs one trivial `Async.parallel` task: 4.2 times slower from the
  whole-program flag alone.
- Suggested fixes, in the direction D139 already names:
  - keep the inline fast path for local counts and send shared or immortal ones to
    `fai_dup`/`fai_drop`; the inline increment already does this, the decrement only for
    possibly immortal types;
  - inline array get and set with the same check, plus the `rc == 1` test as an atomic load;
  - re-read the pool base after suspension points, or keep the inline allocator in functions
    with none.
  An interim step: decide concurrent mode per function, not per program.
- The cost is not in the docs. `llms.txt` and `docs/CLI.md` say nothing about it; only
  `MEMORY.md` and a code comment do.
- `Concurrency` declared in a row but not used is rejected (FAI5001), so a repro has to use it.

Codegen (from fai-008):
- A self-recursive array loop loses the uniquely-owned loop plan if its body calls any other
  function, even only on the exit branch (`array_loop.rs`, `Scan::walk`). Repro:
  `let loop i xs = if i >= 8 then other xs else loop (i + 1) (Array.unsafeSet i 1 xs)` gets
  a reference-count check per iteration; returning `xs` instead does not.
- The range analysis (`bounds.rs`, `integer_in_range`) ignores bitwise operators, so
  `Int.and x 0xFFFFFFFF` can't prove that a retag fits, and every store keeps a `seto` check.
- `fai` needs `FAI_HOME` even when `/opt/fai/bin` is on PATH ("no default compiler").
