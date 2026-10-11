# Run plan: OxCaml (agreed with Chris, 2026-10-12 05:25 AEST)

Read this after `AUTOPILOT.md`. It sets this run's priorities, time box and end-of-run steps.
Everything else in the brief, the runbook and `HILL-CLIMB.md` still applies, including the
"Never without Chris" list. The previous plan (run 9: size, final scoreboard) is in git history;
its results are in the run 9 morning report in `STATUS.md`.

This is the first climb in a language new to the machine, and the first in a language none of
our entries uses. Backlog item 36 has the background; the workshop's set-up notes are in
agentic-hill-climber `examples/primes/next-climbs.md` (summarised here, so you don't need them).

## Limits

- Time box: 6 hours from the session start. Stop starting experiments at 5h15; the final
  scoreboard and shutdown take the last 45 minutes.
- Azure: NZ$25 for the run, no new pools past NZ$20, Spot only, 128 Spot vCPUs, at most 6 pools.
  Every pool's deadline is the run's end; take a pool down as soon as its work is done.
- Check the CPU model line of every log against the pool's intended chip before counting it.
- **Don't touch the ISPC entries.** `hc/champion`, `hc/champion-tables`, `hc/ispc-final` and
  `hc/ispc-final-tables` are frozen for the PR. ISPC builds appear in this run only as controls.
- Write a "Run ... started" event first thing (`st.py`) so the token counter can attribute the
  run, and report main-session and background-agent tokens separately.

## The keep rule

As in run 9 (`HILL-CLIMB.md`, "Acceptance rule"): decide per thread at 1T and 4T on Zen 5 and
Zen 3; Intel AVX2 and Cobalt are gates; all-threads is recorded, not decided.

## What we know about OxCaml (checked 11 October)

- Install: an opam switch, `5.2.0+ox`, from Jane Street's opam repository:
  `opam switch create 5.2.0+ox --repos ox=git+https://github.com/oxcaml/opam-repository.git,default`.
  It builds the compiler from source; expect 30 minutes or more on a 16-vCPU node. Needs
  `autoconf` and glibc.
- **No Alpine.** OxCaml needs glibc, so the runtime stage can't copy into `alpine` as gkpotter's
  OCaml entries do. Use a Debian or Ubuntu slim image.
- x86-64 and Arm64 are supported. **SIMD is x86-64 only** for now, so Cobalt gets a scalar build.
- Not yet known: which SIMD widths OxCaml exposes on x86 (128-bit only, or 256 and 512), and how
  unboxed types and `local` allocation compile in a tight loop. Find out in phase 0.
- The container may or may not reach `opam.ocaml.org` (Chris will say in the start prompt). If it
  can't, every compile happens on a Batch node; batch your edits and keep each round trip worth it.

## Phase 0, first 90 minutes: toolchain and bench

1. **Build the toolchain once per architecture** on a Batch node (`Standard_D16as_v7` for amd64,
   `Standard_D4ps_v6` for arm64; Cobalt will take longer): a Docker image with the switch, timed.
   `docker save | zstd` it to the bench storage account, and have start tasks `docker load` it,
   so a pool comes up in minutes and a pre-empted node doesn't rebuild. The image never leaves our
   storage account. Record the build time per architecture; it matters for the upstream question.
2. **A bench kind `ocaml`** in `hc-pool.sh`, on the pattern of `port`: candidate and champion
   Dockerfiles that start `FROM` the cached image (bench Dockerfiles differ from the submission
   Dockerfile only in that first stage), controls gkpotter's `PrimeOCaml/solution_1` and
   `solution_2` (from `primeimages/ocaml:5.1`), mike-barber's Rust and our ISPC base at
   `hc/ispc-final`. Self-test and paired rounds as usual.
3. If the container can reach `opam.ocaml.org`, build the switch in a background agent here too,
   for local compile checks. Don't wait for it.

If the toolchain won't build on a node within the first 90 minutes, stop and report: that is the
finding, and the plain-OCaml line (below) still runs.

## Phase 1, next two hours: a faithful base, two ways

Both in a new folder, `PrimeOCaml/solution_3` (OxCaml) and `PrimeOCaml/solution_4` (plain
OCaml), on `hc/ocaml-*` branches. Tags `algorithm=base,faithful=yes,bits=1`, own output labels
(`cauldnz-oxcaml-base`, `cauldnz-ocaml-base`), the contest's output format, a self-test and the
size sweep as for the other ports.

- **Plain OCaml 5.2 first**, the control: the design of our ISPC base (one bit per odd number,
  64-bit words, dense small factors from word patterns, the factor-3 set-up, sparse large
  factors), with `Bytes` or `Bigarray` and no allocation in the loop. Built with the upstream
  compiler from `ocaml/opam` or `primeimages/ocaml`, so it needs no special toolchain.
- **Then OxCaml**: the same design with unboxed integers, `local` allocation where it matters,
  and SIMD for the dense phase on x86.

Measure both against gkpotter's entries, Rust and our ISPC base. The gap between the two lines is
what OxCaml's extensions are worth; record it plainly.

## Phase 2: climb (the rest, to 5h15)

Climb the OxCaml base under the keep rule. Borrow from the ISPC, Zig, Rust and C++ climbs and
label each borrowed idea with its source (`kind: borrowed`), so the generalising record stays
honest. Port a kept idea to the plain-OCaml line when it's cheap, so the control stays a fair
comparison. A wheel only if the base has stopped moving.

Record for `docs/generalising.md`: set-up cost (harness lines, toolchain build time), experiments
and keeps, the plain-OCaml vs OxCaml gap at the end, node-minutes.

## Final scoreboard (last 45 minutes)

Per thread at 1T and 4T on Zen 5 and Zen 3, and Cobalt at 1T: OxCaml base, plain-OCaml base,
gkpotter's two entries, mike-barber's Rust and our ISPC base. Final refs as branches
`hc/oxcaml-final` and `hc/ocaml-final` (tag pushes are refused).

## Morning report

Open with whether the toolchain built and how long it took per architecture. Then the
scoreboard, the OxCaml vs plain-OCaml gap and what it came from, keeps and rejects by kind, the
upstream questions this run answers (folder name, build time on the runners, a hosted base image),
and tokens per experiment (main session and background agents separately).
