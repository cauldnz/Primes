# fai-m2: the merged champion's source size, peak memory and in-place updates

Run 11, a measurement made by a background agent in 6.5 minutes (103k tokens, 36 tool calls)
on the container (Intel Xeon 2.10 GHz, 4 vCPUs). The candidate is
`hc/fai-009-champ-plus-005` (f9c0ad0): the OCaml design, the push-built pass for 3, and the 1T
binary without `Concurrency`. Scripts and gdb command files are here; paths in them are
placeholders.

## Source size, like for like

The tokenizer is `tiktoken` 0.14.0 with `o200k_base`, counted with `count.py` (the fai-m1
script, unchanged). "No contracts" removes the `example:` and `forall` lines; the helper
functions only the contracts use stay in.

| Source | lines | nbnc | o200k | o200k, no comments |
|---|---:|---:|---:|---:|
| Fai `Primes.fai` + `PrimesParallel.fai` | 456 | 333 | 5,372 | 4,087 |
| the same, no contracts | 420 | 297 | 4,772 | 3,487 |
| Fai `Primes.fai` alone, no contracts | 367 | 257 | 4,243 | 3,103 |
| plain OCaml `primes.ml` (solution_4) | 326 | 250 | 4,229 | 3,056 |

The Fai program with the same design is larger than the OCaml one: 13% more tokens without
contracts (4,772 against 4,229) and 27% more with them. Writing the 1T program apart from the
threaded one costs 529 tokens.

## Peak memory

Peak RSS from `getrusage(RUSAGE_CHILDREN)` in a fresh Python per run; 3 runs each, medians.

| Binary | peak RSS | passes |
|---|---:|---|
| Fai `primes` (1T) | 11.2 MB | 5,406 |
| Fai `primes-parallel` (4 threads) | 11.2 MB | 7,136 |
| plain OCaml `primes` (1T, then 4 threads, one process) | 194 MB | 21,369 / 49,485 |

Notes on the memory figures:
- **Fai.** Fai's reference counting frees each pass's sieve as it goes.
- **OCaml.** OCaml's figure comes mostly from the multi-domain runs, where the entry raises the
  GC space overhead to 1,000 (run 10). Its 1T-only figure was not measured here.

## In-place updates

The check used gdb on every allocation site, including the inline pool path that the 1T binary
uses for small objects.

**`PRIMES_TEST=1 ./primes`.** All 13 sizes pass, with exactly 13 sieves and 13 scratch arrays
allocated. None of the following was ever reached:
- the inline growth paths in `startSieve`, `pushThree` and `pushZeros`;
- `fai_array_push`;
- `fai_array_set`.

**A 5-second 1T run.** It made 1,841 passes, with 1,841 sieves and 1,841 scratch arrays. There
were no copies, no grows and no runtime set calls.

**A 5-second `primes-parallel` run under gdb.** It made 1,349 passes, with 1,349 sieves and
scratch arrays, and 0 hits on the copy-path allocation sites inside `fai_array_push` and
`fai_array_set`.

Every sieve update happens in place. Perceus reuse holds for this program.
