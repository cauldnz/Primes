# Fai issue drafts (for Chris to post; not filed)

Two issues for https://github.com/Krzysztof-Cieslak/fai. They were drafted from
`drafts/fai-notes.md` after a cold read as the author would see them. Both repros were rebuilt
and timed on 17 October 2026: Fai 0.1.0 (release commit ca5b9c8), x86-64 Linux, Intel Xeon
2.1 GHz with 4 vCPUs, installed from the release assets, `FAI_HOME` set to the install directory.

---

## Issue 1: one use of `Concurrency` makes every `Array` access in the program an out-of-line call

**Summary.** With `Concurrency` in `main`'s effect row, a single-threaded `Array Int` loop runs
about 3x slower than the same loop without it, even when the only concurrent work is one
trivial task and the array never leaves `main`.

**Repro.** Two files, identical except for `main`.

`a/Repro.fai`:

```fai
module Repro

fill : Int -> Int -> Array Int -> Array Int
let fill i n a =
  if i >= n then
    a
  else
    let w = Int.and i 4095
    fill (i + 1) n (Array.unsafeSet w (Int.or (Array.unsafeGet w a) i) a)

passes : Int -> Int -> Int
let passes k acc =
  if k = 0 then acc else passes (k - 1) (acc + Array.unsafeGet 7 (fill 0 1000000 (Array.repeat 4096 0)))

main : Runtime -> Unit / { Console }
let main rt = rt.console.writeLine (Int.toString (passes 200 0))
```

`b/Repro.fai`: the same, with this `main`:

```fai
main : Runtime -> Unit / { Console, Concurrency }
let main rt =
  let t = Async.parallel rt.concurrency [fun u -> 0]
  rt.console.writeLine (Int.toString (passes 200 (List.length t)))
```

```sh
cd a && fai build --no-daemon --out repro Repro.fai && time ./repro
cd b && fai build --no-daemon --out repro Repro.fai && time ./repro
```

**Observed.** Wall time over three runs each:
- `a` (no `Concurrency`): 0.44s, 0.40s, 0.41s.
- `b` (one trivial task): 1.39s, 1.24s, 1.37s.

The disassembly of `fill` in `b` calls `fai_array_get_borrowed` and `fai_array_set` on every
iteration. In `a` both are inlined, and the loop is specialised for a uniquely owned array.

**Expected.** Close to the same time for `fill`, since the array is local to `main`. Failing
that, the cost documented where agents will see it (`llms.txt`, `docs/CLI.md`). Today it is
mentioned only in `docs/MEMORY.md` (D139) and a comment in `array_prim`.

**Pointers.**
- `crates/fai-driver/src/entry.rs`: the program-wide `concurrent` flag is set from `main`'s
  effect row.
- `crates/fai-codegen/src/emit.rs`: `array_prim` returns `None` when it is set.

D139 already lists per-object inline reference counting as future work; a per-function mode
might be another option.

---

## Issue 2: the range analysis ignores a literal mask in `Int.and`

**Summary.** `Int.and x 0xFFFFFFFF` doesn't let the range analysis prove that the result fits an
unboxed `Int`. So storing it into an `Array Int` keeps an overflow check (`seto` and a cold
`make_int`) on the retag. Binding the same mask to a local first removes the check.

**Repro.** Two files, identical except for the mask.

`m1/Mask.fai` (literal mask):

```fai
module Mask

fill : Int -> Int -> Array Int -> Array Int
let fill i n a =
  if i >= n then
    a
  else
    let w = Int.and i 4095
    fill (i + 1) n (Array.unsafeSet w (Int.and (Int.or (Array.unsafeGet w a) (Int.shiftLeft 1 (Int.and i 31))) 0xFFFFFFFF) a)

passes : Int -> Int -> Int
let passes k acc =
  if k = 0 then acc else passes (k - 1) (acc + Array.unsafeGet 7 (fill 0 1000000 (Array.repeat 4096 0)))

main : Runtime -> Unit / { Console }
let main rt = rt.console.writeLine (Int.toString (passes 200 0))
```

`m2/Mask.fai`: the same, with the mask bound to a local:

```fai
  else
    let m = 0xFFFFFFFF
    let w = Int.and i 4095
    fill (i + 1) n (Array.unsafeSet w (Int.and (Int.or (Array.unsafeGet w a) (Int.shiftLeft 1 (Int.and i 31))) m) a)
```

```sh
fai build --no-daemon --out mask Mask.fai
objdump -d --no-show-raw-insn mask | awk '/<fai2__x4dask__fill>:/{f=1} f&&/^$/{exit} f' | grep -c seto
```

**Observed.**

| Version | `seto` in `fill` | Wall time over three runs |
|---|---:|---|
| `m1` (literal mask) | 3 | 0.42s, 0.39s, 0.41s |
| `m2` (local mask) | 1 | 0.34s, 0.35s, 0.40s |

Both print 25600. In a larger loop with four stores per iteration, the local mask made the
program 10-16% faster.

**Expected.** Both versions prove `0 <= result <= 0xFFFFFFFF` and retag without the check.

**Pointers.**
- `crates/fai-core/src/bounds.rs`: `transfer_mask` records the bound only when the mask is a
  term known to be non-negative.
- In the same file, `atom_term` accepts locals and the literal 0 but not other literals.

**Related, lower priority.** `bounds.rs` has no transfer rules for:
- `Int.shiftRightLogical x k`, which gives `0 <= result < 2^(64-k)`;
- `Int.or` and `Int.xor` of two bounded non-negative operands.

With them, a word index such as `shiftRightLogical i 5` would also get its `>= 0` fact.
