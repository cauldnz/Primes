# fai-015: a survey of Fai's distinctive features, and why its candidate was not measured

Run 11, a background agent in 7.5 minutes (128k tokens, 52 tool calls), after Chris asked that
the climb use Fai's unique features. The branch is `hc/fai-015-fai-feature` (6061afc). It was
not submitted to Azure.

## What it built, and why it stopped there

The agent found that Fai's `ProcessHost.Process` capability starts native processes without
switching the program into concurrent mode. It rebuilt the multi-thread run as one worker
process per thread, each running the fast inline kernel. Locally that gave 3.4 times the 4T
passes (18,824 against 5,480, five interleaved rounds), with 1T unchanged.

Chris had ruled out multi-process runs earlier the same day ("We shouldn't run multiple
processes"), so the candidate was not measured or merged. The finding stands: in Fai 0.1.0,
processes are the only way to get the inline array path on more than one core.

## The feature survey

| Feature | Expected effect on this sieve | Used in run 11? |
|---|---|---|
| Perceus reference counting with in-place reuse | every update in place, 11 MB peak | yes (all experiments) |
| Effect rows decide the compile mode (`Concurrency` makes the whole program call out for array access) | 3x at 1T without `Concurrency` | yes (fai-005, fai-011) |
| Owned-loop specialisation of self-recursive array loops | refcount checked once per loop | yes (kept by every kernel) |
| Range analysis (bounds.rs) removing retag and bounds checks | retag check removed with a local mask | yes (fai-014) |
| `example` and `forall` contracts | checks at `fai check`; no optimisation use | yes (46 properties) |
| `ProcessHost.Process` without `Concurrency` | 3.4x at 4T as processes | built, not used (Chris: no processes) |
| `foreign` fork and `_exit` | same as processes, no startup | not tried (same ruling) |
| `FAI_WORKERS`, `Async` variants | all keep concurrent codegen | not useful |
| Array split and join, slices | no such API for `Array Int`; would be segmentation | not available |
| `requires`/`ensures` contracts used by the optimiser | not in the language | not available |
| Inline or specialise annotations | not in the language (inlining is automatic) | not available |
| `Bytes`, Bool arrays, packed types | `Bytes` is immutable; Bool slots break bits=1 | not usable |
| `fai query caps` | proves a binary is not in concurrent mode | used as a check |

## Notes for the Fai author

The agent drew three points from the survey:
- **Process API.** `ProcessHost` has no "spawn self" helper, and its `Options` and `Command`
  records are verbose.
- **Docs gap.** `llms.txt` describes the `process` package as needing `Concurrency`, but the
  raw `ProcessHost.native` it wraps doesn't. This shows only in `samples/NativeProcess.fai`.
- **The real fix.** A per-task owned path, or a `parallelMap` over unique arrays that keeps
  single-threaded codegen in each task, would make in-language threads competitive. Today
  processes are 3.4 times faster at 4T.
