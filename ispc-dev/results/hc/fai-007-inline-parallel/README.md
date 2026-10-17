# fai-007: inline array access in a parallel Fai program (finding: no safe route)

Run 11, a research question answered by a background agent in about 3 minutes (110k tokens,
34 tool calls). Nothing was built or pushed. Paths are in the Fai repository at release commit
ca5b9c8.

## Why `Concurrency` slows every array access

The compiler decides concurrent mode once for the whole program. It is on when the effect row
of `main`, or of the runtime value, includes `Concurrency` or `Net`
(`crates/fai-driver/src/entry.rs:154-156, 197-199`). The flag reaches every function's code
(`backend.rs`) and is part of the build cache key. In concurrent mode the compiler changes
four things:

- every reference-count increment goes to `fai_dup` and every decrement to `fai_drop`
  (`emit.rs:2334-2376`);
- the inlined pool allocator is skipped, because a task can migrate between workers
  (`emit.rs:1226-1236`);
- `array_prim` returns no inline code, so each array get and set is a runtime call
  (`emit.rs:4182-4189`);
- the runtime's biased reference counts make a value shared, and atomic, when it crosses a
  task boundary (`fai_mark_shared`, `lib.rs:1845-1877`; `docs/MEMORY.md` D138, D139).

`docs/MEMORY.md` D139 names per-object inline reference counting as "a future refinement".

## No supported switch

There is no flag, attribute or pragma that changes concurrent mode. `fai build --help` and
`docs/CLI.md` list none, and nothing in the compiler treats a task's own array as task-local.
Hiding `Concurrency` from the effect checker would be a data race, so it was not built:

- **Reference counts.** The inline decrement checks the shared state only for possibly
  immortal types (`emit.rs:2540-2585`). Captured records and closures would be decremented
  non-atomically, racing other threads.
- **Allocator.** The cached pool base goes stale when a task migrates.
- **Root task.** `main` would not run as the scheduler's root task.

## Processes, recorded only

Fai can start processes. `std/io/ProcessHost.fai` defines a `Process` interface, and the raw
effect doesn't switch on concurrent mode. Chris ruled it out on 17 October: the
multi-thread runs stay one program with threads. Nothing was built.

## Minimal repro

`st/Repro.fai` and `cc/Repro.fai` run the same loop: 200 passes over a fresh 4,096-slot
`Array Int` with 1M read-OR-write updates each. They differ only in `main`. The `cc` version
also runs a single trivial `Async.parallel` task, and the loop itself runs single-threaded on
`main`. `bench.py` times them.

| build | wall s (2 rounds) |
|---|---|
| no `Concurrency` (`st`) | 0.30, 0.29 |
| one trivial task (`cc`) | 1.21, 1.29 |

That is about 4.2 times slower, from the whole-program flag alone.
