# fai-000/fai-001: a base sieve in Fai, feasibility

Run 11, phase 0. Can the drag-race base sieve be written in Fai 0.1.0, a strict, pure
functional language with Perceus reference counting, and how fast is it? Yes, it can, in
about 280 lines with its contracts, and it ran at about half the speed of the same loop in OCaml.

- Branch `hc/fai-base`; the solution is `PrimeFai/solution_1/`.
- Machine: shared four-vCPU Intel Xeon container. Local screening only, not a decision.
- Doc references are to the Fai repository at release commit ca5b9c8 (`llms.txt`, `docs/`,
  `std/`, `crates/`).

## Install

Fai 0.1.0, release commit ca5b9c8, installed at `/opt/fai`. The Fai launcher ignores
`SSL_CERT_FILE`, so it could not download through this container's TLS-inspecting proxy. The
release assets were fetched with curl, served from a loopback mirror and installed through
`FAI_RELEASE_BASE_URL`, the documented mirror mechanism (`docs/INSTALLATION.md:95-100`:
"`FAI_RELEASE_BASE_URL` overrides the releases root for controlled mirrors ... loopback HTTP
is supported for local qualification"). The Dockerfile uses the normal versioned installer
(`install.sh --version 0.1.0`), which should work on a host without the proxy. The Docker
build has not been run here.

## Feasibility answers

**(a) Mutable buffers, in place or copied.** There is no mutation in the language
(`llms.txt:119`: "There is no mutation"). `Array 'a` is contiguous, and `set`/`push`
update in place when the array is uniquely owned and copy when it is shared
(`llms.txt:1456`; `docs/MEMORY.md:3019-3021`). `Bytes` is immutable, with no set at all
(`llms.txt:1684`, `std/primitives/Bytes.fai`), so `Array Int` is the only writable buffer.
`Array Int` elements are tagged 63-bit slots; a value outside that range is boxed on the heap
(`docs/MEMORY.md:3101-3104`). A full 64-bit word therefore allocates on each store once its top
bits are set.

Timing probe (1M-element `Array Int`):

| Probe | Time |
|---|---|
| 1,000 single-element `unsafeSet`s, array uniquely owned | 4ms (includes the 8MB `Array.repeat`) |
| 1,000 `unsafeSet`s while the source array is still referenced | 3,868ms (one 8MB copy per update) |
| 100 sweeps of 1M read-OR-write updates, unique | 169ms (1.7ns per update) |

Direct evidence, not timing alone. Fai has no allocation counter in release builds (the
runtime's `ARRAY_COPIES` counter exists only with debug assertions or the `allocation-stats`
feature, `crates/fai-runtime/src/lib.rs:853-856`) and no `--emit` option. But the generated
code is ordinary x86-64 with symbols:

- `objdump -d` of the sieve shows its marking loop (`fai2__x50rimes__clear_x4dultiples`) calling
  `fai_array_get_borrowed` and `fai_array_set` once per multiple and keeping the array pointer
  that `fai_array_set` returns.
- `fai_array_set` checks `rc_load(p) == 1` and writes the slot in place; otherwise it allocates
  a copy (`crates/fai-runtime/src/lib.rs:2483-2499`). The two calls to `alloc_obj` on the copy
  path are at `fai_array_set+281` and `fai_array_set+440` in both binaries below.
- A gdb breakpoint count on those two sites: the shared-array probe hit them 1,000 times (one
  per update, as expected). The sieve's full `PRIMES_TEST=1` run (13 sizes up to 10^8)
  hit them 0 times. Every sieve store is in place.
- Peak RSS agrees: 11.1MB for the Fai benchmark runs, against 11.1MB for the plain OCaml loop.

**(b) Bitwise ops and shifts.** One integer type, `Int`, 64-bit signed (`llms.txt:185`), with
`Int.and/or/xor/complement/shiftLeft/shiftRight` (arithmetic) and `shiftRightLogical`
(`llms.txt:1790-1802`). No unsigned type. Arithmetic wraps (`0x7fffffffffffffff + 1` printed
`-9223372036854775808`). Shift counts are taken mod 64, which is undocumented: `shiftLeft 1 64`
gave 1 and `shiftLeft 1 65` gave 2.

**(c) Loops and tail calls.** No loop syntax; self-tail calls compile to loops
(`llms.txt:2764-2768`, `samples/TailLoops.fai`). A 100M-iteration tail-recursive loop ran in
35-59ms with constant stack. Local `let` functions cannot recurse (`llms.txt:105-108`), so
every loop is a private top-level function.

**(d) Threads.** `Concurrency` is a capability with structured `scope`/`spawn`/`await`, and
`Async.parallel` runs a list of thunks (`llms.txt:986-1048`). Tasks run on an M:N scheduler
whose worker count defaults to the host's available parallelism, override `FAI_WORKERS`
(`llms.txt:1045-1047`). Four independent sieve tasks gave 3.5-4.1 times the one-thread passes.
There is no API for the hardware thread count; the program counts the `processor` lines of
`/proc/cpuinfo`.

**(e) Clock.** The only clock is `Clock.now : Unit -> Int`, milliseconds
(`std/core/Prelude.fai:160`). It is wall-clock: the runtime reads `SystemTime::now()`
(`crates/fai-runtime/src/lib.rs:4759-4769`). No monotonic clock and no sub-millisecond time.
A monotonic one would need a `foreign` binding plus a C shim, since `clock_gettime` takes a
struct pointer.

**(f) Printing.** `Console.writeLine`/`write`/`writeError` through the runtime capability
(`llms.txt:735-739`). There is no exit-status API at all; `main` returns `Unit`. The solution
adds an `Exit` capability over libc's `exit` (`foreign "exit" cExit : Int -> Unit / { Exit }`),
which the AOT linker resolves with no `fai.toml`; stdout is flushed. The probe exited with
status 3 as asked.

**(g) Bounds checks.** `get`/`set` return `Option`. `unsafeGet`/`unsafeSet` return bare values
but still check and abort (`docs/MEMORY.md:3033-3037`). An out-of-bounds `unsafeGet` printed
"fai runtime error: array index out of bounds" and exited with SIGABRT (134). There is no
unchecked access.

**(h) SIMD.** None. No vector types in `std/`, and no SIMD in the docs; the codegen is
Cranelift.

**(i) arm64.** Supported: "Linux/glibc, macOS, and Windows/MSVC on x86-64 and ARM64"
(`docs/INSTALLATION.md:22-23`). Cross-compilation is not: `--target` "currently supports the
host only" (`docs/CLI.md:77`). Not tested here.

**(j) Standalone executable.** `fai build Primes.fai --out primes` compiles ahead of time
(Cranelift, then the system linker; `docs/CLI.md:459-473`). The linker is `cc`, or `$CC`
(`crates/fai-driver/src/backend.rs:1665`), so a C toolchain must be installed. `--release` is
"accepted; no effect yet" (`fai build --help`). `--no-daemon` builds in-process. The binary is
dynamically linked to glibc, libm and libgcc_s only. A build took 0.5-1.1 seconds.

## The sieve

`PrimeFai/solution_1/Primes.fai`:

- One bit per odd number, 32 bits per `Array Int` element. With 64 bits per element, the
  words with their top bits set were boxed on every store: 429 passes against 1,097. A 62-bit
  layout (divide by 62) ran 969.
- Each multiple is its own read-OR-write, from p²/2 in steps of p bits (2p in value). The next
  factor comes from scanning odd numbers upward from 3. A new array every pass; nothing kept.
- Contracts: `example`s for the counts at 1, 2, 3, 10, 100, 127, 1000 and 16383; four `forall`
  laws over sizes up to 4999 (count matches the list, no even number above 2, no odd divisor up
  to the square root, nothing above the size).
- Output `cauldnz-fai-base;<passes>;<seconds>;<threads>;algorithm=base,faithful=yes,bits=1`,
  for one thread, all hardware threads and, above four, exactly four. Seconds are wall-clock
  milliseconds (see e).
- `PRIMES_TEST=1` self-test: the OCaml entry's 13 sizes, 1 to 10^8. All 13 pass, exit 0. A
  mutant gives exit 1.

## Local speed (screening only)

5-second one-thread runs, three interleaved rounds. "OCaml solution_4" is
`PrimeOCaml/solution_4` from `origin/hc/ocaml-final`, built with OCaml 5.2 flambda per its
`build.sh`; it uses dense word patterns and an unrolled sparse loop. "OCaml same loop" is a
20-line OCaml copy of the Fai loop (32 bits per `int array` element, one OR per multiple),
built the same way, to separate the language from the algorithm.

| Round | Fai | OCaml solution_4 | Fai (2nd set) | OCaml same loop |
|---|---|---|---|---|
| 1 | 1,048 | 21,486 | 1,199 | 2,361 |
| 2 | 1,069 | 23,793 | 1,112 | 2,336 |
| 3 | 1,200 | 21,189 | 1,099 | 2,184 |
| Median | 1,069 | 21,486 | 1,112 | 2,336 |

- Against solution_4, Fai runs about 20 times fewer passes. Against the same loop in OCaml,
  2.1 times fewer. Fai is well short of the 100x stop line.
- Four threads: Fai 3,966-4,360 passes; solution_4 44,598-49,013.
- Peak RSS: Fai 11.1MB; OCaml same loop 11.1-11.2MB; solution_4 129-193MB (its multi-domain
  run raises the GC space overhead).
- Where the factor of two goes: each mark calls two runtime functions,
  `fai_array_get_borrowed` and `fai_array_set`, each with a bounds check, and `fai_array_set`
  also checks the reference count and drops the old element. OCaml inlines the load and store.
- Fai cannot narrow that gap from the source: no unchecked access, no wider unboxed word and
  no byte buffer to write. Unrolling or a pattern-based dense pass would cut the number of
  marks but not the cost of each.

## What I had to read

| Feature | Source used | Enough? |
|---|---|---|
| Syntax, layout, locals, loops | `llms.txt` sections 2, 6, 17; `samples/TailLoops.fai` | Yes. The rule that local `let` cannot recurse (`llms.txt:105`) saved a cycle. |
| Arrays and in-place update | `llms.txt:1450-1515`; `docs/MEMORY.md:2995-3040` | Mostly. `llms.txt:1457` says the `unsafe*` variants "skip the bounds check", but `MEMORY.md:3035-3037` and the runtime show they check and abort. |
| Int boxing in arrays | `docs/MEMORY.md:3093-3104` (D119) | Only in MEMORY.md. `llms.txt` says only "Int (64-bit signed)"; nothing there warns that storing a 64-bit value in an array allocates. Found by timing, then confirmed in MEMORY.md. |
| Bit ops | `llms.txt:1790-1802` | Yes, except shift counts of 64 or more (undocumented; probed). |
| Concurrency | `llms.txt:986-1048`; `samples/ConcurrencyDemo.fai` | Yes. |
| Clock | `llms.txt` section 10 (interface list); `std/core/Prelude.fai:158-161`; runtime source | No. The docs never say the clock is wall-clock or its unit; the unit and source came from `crates/fai-runtime/src/lib.rs:4759`. `llms.txt` lists only `now` for `Clock`; the Prelude also has `localOffset` and `sleep`. |
| Exit status | `llms.txt` sections 10 and 15; `samples/NativeCapability.fai` | No exit API is documented anywhere. The `foreign` route came from the NativeCapability sample; that a libc symbol links with no `fai.toml` was found by trying it. |
| Contracts | `llms.txt` section 12 | Mostly. Section 12 does not say that a generated `Int` stays within the max size (100 by default); I saw it in the `fai test` banner, and the first laws covered sizes 0-100 only until I spread the input. |
| AOT build and linker | `docs/CLI.md:159-170, 459-473`; `fai build --help`; `crates/fai-driver/src/backend.rs` | Partly. The docs say "the system linker"; that it is `cc` (or `$CC`) is in the source. `--release` having no effect is only in `--help`. |
| Hardware threads | `llms.txt:1045-1047` | No API; the docs mention only the scheduler default. |
| Install and mirror | `docs/INSTALLATION.md` | Yes. |

## For the Fai author

- Performance gap: an `Array Int` store of a value outside 63 bits boxes it. Repro: set every
  bit 0-63 in a 1M-element array, then sieve with 64 bits per element: 429 passes against
  1,097 with 32 bits.
- Performance gap: `Array.unsafeGet`/`unsafeSet` compile to out-of-line calls
  (`fai_array_get_borrowed`, `fai_array_set`) with a bounds check, a reference-count check and
  a drop of the old element on every store; an inline fast path for unique `Array Int` would
  likely close most of the 2.1 times gap to OCaml.
- Docs: `llms.txt:1457` says `unsafe*` skip the bounds check; they abort instead
  (`docs/MEMORY.md:3035`).
- Docs: `Clock.now` is wall-clock milliseconds (`SystemTime`); neither fact is documented, and
  there is no monotonic clock.
- Missing: no way to set the process exit status from `main`.
- Undocumented: `Int.shiftLeft`/`shiftRight` take the count mod 64 (`shiftLeft 1 64 = 1`).
- `FAI6001` for a failing `example: a = b` gives the line but not the two values.
- `fai build --release` is accepted but does nothing in 0.1.0.
