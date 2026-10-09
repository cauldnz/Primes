# CLAUDE.md (ispc-dev branch only)

This fork is for the ISPC entry to the Primes drag race. Start with `ispc-dev/HANDOFF.md`.

- The submission lives in `PrimeISPC/solution_1/`. Everything else under `ispc-dev/` is
  development material and must never be part of the PR.
- Work on `ispc-dev`; land solution-only commits on `ispc` (the PR branch). This file exists
  only on `ispc-dev`.
- Don't modify other languages' solutions or upstream files.
- After any change to `primes.ispc`: `sh build.sh && PRIMES_TEST=1 ./primes` must exit 0, and
  compare speed with interleaved runs against the previous build.
- Keep the output tags honest (`algorithm=wheel,faithful=yes,bits=1`); re-check the
  faithfulness rules in `CONTRIBUTING.md` if a change keeps state across passes.
- Azure benchmarking: `ispc-dev/azure-epyc-bench.sh`. It deletes its resource group on exit;
  confirm nothing is left running afterwards (`az group list -o table`).
