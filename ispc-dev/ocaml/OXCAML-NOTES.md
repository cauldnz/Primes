# OxCaml notes (experiment ox-001)

What the OxCaml compiler offers for a fast bit sieve, checked on a real build. Compiler:
`ocaml-variants.5.2.0+ox`, which pulls `oxcaml-compiler.5.2.0minus39` (flambda2, runtime 5,
multidomain, poll insertion). Build host: a 4-vCPU cloud container, Intel Xeon at 2.8GHz with
AVX2 and AVX-512F. Probe sources are in `probe/`; their assembly listings are in `probe/asm/`.

## Build

```sh
export OPAMROOT=/opt/opam-ox
opam init --bare --disable-sandboxing -n -y
opam switch create 5.2.0+ox \
  --repos "ox=git+https://github.com/oxcaml/opam-repository.git,default" -y
```

The switch build took 1,183 seconds (19 min 43 s) on four vCPUs. Nearly all of it is the
compiler package, which builds a bootstrap OCaml 5.4.0, dune and menhir, then OxCaml twice
(boot compiler, then the final one). The `.guard` packages install in seconds.

One snag, specific to this container: its egress proxy refuses GitHub archive tarballs
(`github.com/<owner>/<repo>/archive/...`, HTTP 403) but serves git clones. Two sources come
from such URLs: the OxCaml tag `5.2.0minus-39` and the OCaml `5.4.0` tag. The fix was to clone
each tag shallowly, rebuild the tarball with
`git archive --format=tar --prefix=<repo>-<tag>/ HEAD | gzip -n`, and drop it into
`$OPAMROOT/download-cache/sha256/<first two hex>/<sha256>`. The rebuilt tarballs matched the
opam checksums byte for byte. On an ordinary host (the Azure Batch image in
`oxcaml.Dockerfile`) none of this is needed.

Compile command used for every probe (single file, no ocamlfind, no dune):

```sh
ocamlopt -O3 -S probe.ml -o probe              # scalar and domains probes
ocamlopt -O3 builtin_stubs.c -S vor.ml -o vor  # SIMD probe (see 2a for why the .c)
```

`ocamlopt -config` reports `flambda2: true`. No `-extension` flag was needed for `int64#`,
`int#`, `let mutable`, 128-bit or 256-bit vectors, or modes: the default extension universe
is `alpha` and these are on.

## 2a. SIMD

Widths: 128-bit and 256-bit work. 512-bit does not.

- 128-bit types: `int8x16 int16x8 int32x4 int64x2 float32x4 float64x2`, plus unboxed forms with
  a trailing `#` (`int64x2#`).
- 256-bit types: `int8x32 int16x16 int32x8 int64x4 float32x8 float64x4`, plus `#` forms.
- 512-bit: `int64x8` exists only under `-extension simd_alpha`, and a 512-bit load from Bytes
  with `-favx512f` crashes the amd64 emitter (`Fatal_error` on `unaligned vec512`). The
  intrinsic generator lists no AVX-512 instructions. The docs say "NEON and AVX512 is coming
  soon".

ISA flags: `-f<ext>` / `-fno-<ext>` for `popcnt lzcnt sse3 ssse3 sse41 sse42 clmul bmi bmi2
avx avx2 f16c fma avx512f prefetchw prefetchwt1`. All Haswell extensions (up to AVX2, BMI2,
FMA) are on by default if the CPU that built the compiler had them, which it did here. The
build therefore emits VEX-encoded code (`vmovupd`, `vorps`) by default. Pass `-fno-avx` for a
portable SSE-only binary, or rebuild the compiler on the target, since the defaults come from
the build machine's `configure`.

Intrinsics are `[@@builtin]` externals. The first string is the bytecode name, the second the
native name that the backend turns into an instruction:

```ocaml
external or128 : int64x2 -> int64x2 -> int64x2
  = "caml_vec128_unreachable" "caml_sse_vec128_or"
  [@@noalloc] [@@unboxed] [@@builtin]

external or256 : int64x4 -> int64x4 -> int64x4
  = "caml_vec256_unreachable" "caml_avx_vec256_or"
  [@@noalloc] [@@unboxed] [@@builtin]
```

Other names seen in `oxcaml/tests/simd/amd64/builtins.ml`: `caml_sse_vec128_and`,
`caml_sse_vec128_andnot`, `caml_sse_vec128_xor`, `caml_sse2_int64x2_sll`,
`caml_sse2_int64x2_slli` (immediate shift as `(int[@untagged])`), `caml_avx2_int64x2_sllv`,
`caml_sse41_int64x2_extract`, `caml_avx_vec256_testnzc`, `caml_int64x2_low_of_int64`,
`caml_int64x2_low_to_int64`, `caml_int64x2_const1` (constant argument). The `ocaml_simd`
library in the OxCaml opam repository wraps all of these (`Ocaml_simd_sse`,
`Ocaml_simd_avx`), but needs dune; declaring the externals by hand keeps a single-file build.

Link snag: the object file still lists the native names of builtins even though every call
is inlined, so the link fails with `undefined reference to caml_sse_vec128_or`. The OxCaml
test suite links dummy C stubs for this (`stub_builtins.c`); `probe/builtin_stubs.c` does the
same for the two names used. They are never called.

Loads and stores on Bytes are compiler primitives, not intrinsics. Name pattern:
`%caml_bytes_{get,set}u{128,256}` then `u` for unchecked, then `#` for an unboxed vector:

```ocaml
external get128 : bytes -> int -> int64x2 = "%caml_bytes_getu128u"
external set128 : bytes -> int -> int64x2 -> unit = "%caml_bytes_setu128u"
external get256 : bytes -> int -> int64x4 = "%caml_bytes_getu256u"
external set256 : bytes -> int -> int64x4 -> unit = "%caml_bytes_setu256u"
```

Bytes only gets unaligned forms (the GC may move it). Bigstrings get aligned and unaligned:
`%caml_bigstring_geta128u`, `%caml_bigstring_getu256u` and so on. The same family exists for
`int64# array`, `nativeint# array`, `int32# array`, `float array` and others
(`%caml_unboxed_int64_array_get128u`). Every primitive also has `_indexed_by_int64#`,
`_indexed_by_nativeint#` and smaller-index variants.

## 2b. Unboxed integers and flags

Types: `int64#`, `int32#`, `nativeint#`, `int#` (untagged 63-bit int), `int8#`, `int16#`,
`float#`, `float32#`. Literals: `#123L`, `#789n`. Arrays of them are flat (`int64# array`).
Arithmetic comes from `Stdlib_upstream_compatible.Int64_u` and `Stdlib_stable.Int_u`, which
are thin wrappers over primitives you can declare yourself:

```ocaml
external box : int64# -> int64 = "%box_int64"
external unbox : int64 -> int64# = "%unbox_int64"
external get64u_u : bytes -> int -> int64# = "%caml_bytes_get64u#"
external get64x : bytes -> int64# -> int64 = "%caml_bytes_get64u_indexed_by_int64#"
external of_int : int -> int# = "%int#_of_int"
external add_u : int# -> int# -> int# = "%int#_add"
```

What the probes showed:

- flambda2 already unboxes `Int64` values inside a loop. `%caml_bytes_get64u` with plain
  `Int64.logand` gives the same code as the `int64#` primitives: no allocation, no boxing.
- Tagged `int` costs about four extra instructions per iteration. Turning a tagged bit index
  into a byte offset takes `shrq; orq $1; leaq -7(,r,8); sarq $1`, and the shift count needs
  `andl $127; sarq $1`.
- `int#` does not help: it keeps 63-bit wrap-around semantics, so every add gets a
  `salq $1; sarq $1` fix-up and every logical shift gets a 63-bit mask. It was the slowest
  unchecked variant.
- An `int64#` loop counter with `_indexed_by_int64#` loads gives the cleanest loop: 17
  instructions against 19 for tagged ints.
- `Bytes.get_int64_le` / `set_int64_le` bounds-check both the load and the store and reload
  the Bytes header length every iteration: 35 instructions, twice as slow.

Flags: `-O3` is the top normal level (`-O4` adds the experimental "reaper" pass). `-unsafe`
only drops checks on `.()` and `.[]` syntax; the `u` primitives are unchecked anyway.
`-unboxed-types` exists but only changes how unannotated types are represented, and isn't
needed. Two flags worth knowing: `-zero-alloc-check` (with `[@zero_alloc]` on a function, it
fails the build if the function can allocate) and `-vectorize` (experimental
auto-vectoriser). `-inline`, `-rounds` and the `-flambda2-expert-*` knobs were left at
default.

## 2c. `local_` and stack allocation

Locality decides whether a value goes on the stack (`local`) or the heap. You can force it
with `stack_ { ... }` or `local_`. A loop that allocates nothing gains nothing. In the probes,
`ref` cells used as loop counters were already turned into registers, including refs captured
by a local closure, so there was nothing left to put on the stack. `local_` matters only where
a hot path builds a tuple, closure or boxed number that escapes flambda2's unboxing.

## 2d. Multicore

`Domain.spawn` works. OxCaml tags it with two alerts (`do_not_spawn_domains`,
`unsafe_multidomain`); alerts are warnings by default, and an attribute silences them:

```ocaml
(Domain.spawn [@alert "-do_not_spawn_domains"] [@alert "-unsafe_multidomain"]) f
```

`Domain.Safe.spawn : (unit -> 'a) @ portable once -> 'a t` is the mode-checked version. The
closure must be `portable`, and so must everything it calls, externals included:

```ocaml
external set64u : bytes -> int -> int64 -> unit @@ portable = "%caml_bytes_set64u"
let sieve @ portable = fun () -> ...   (* builds its own Bytes *)
let d = (Domain.Safe.spawn [@alert "-do_not_spawn_domains"]) sieve
```

A plain top-level `let sieve () = ...` is inferred `nonportable` and is refused. The probe runs two
batches of four domains (one per spawn style), each domain doing 100 sieves of 1,000,000:
0.73 s wall, 2.40 s user, about 3.3 times parallel on four vCPUs. `Domain.recommended_domain_count ()` returned 4.

## 3. Hot loops

Probe (i), `probe/clear64.ml`: odd-only bit sieve to 1,000,000, clearing bits in a Bytes
buffer of 64-bit words. Instructions per inner iteration, from the `-S` output, and the best
of six runs (each 200 sieves, CPU time):

| Variant | Read/write | Instr/iter | ms per sieve |
|---|---|---|---|
| stdlib | `Bytes.get_int64_le` / `set_int64_le` | 35 | 1.99 |
| unsafe | `%caml_bytes_get64u` / `set64u`, `Int64` ops | 19 | 1.11 |
| unboxed | `%caml_bytes_get64u#` / `set64u#` | 19 | 1.11 |
| bytes8 | `Bytes.unsafe_get` / `unsafe_set`, byte-wide | 20 | 1.12 |
| untagged | `int#` counter | 21 | 1.35 |
| int64# | `int64#` counter, `_indexed_by_int64#` | 17 | 1.04 |

The 17-instruction loop:

```asm
.L296:
  movq %rbx,%rsi ; shrq $6,%rsi ; salq $3,%rsi        # word offset
  movl $63,%edx ; movq %rbx,%rcx ; andq %rdx,%rcx      # bit number
  movl $1,%edx ; salq %cl,%rdx ; xorq $-1,%rdx         # ~(1 << bit)
  movq (%rax,%rsi),%rcx ; andq %rdx,%rcx ; movq %rcx,(%rax,%rsi)
  addq %rdi,%rbx
  cmpq (%r14),%r15 ; jbe .L313                         # safepoint poll
  cmpq $500000,%rbx ; jl .L296
```

Every loop carries a two-instruction safepoint poll (`cmpq (%r14),%r15; jbe`), because the
opam compiler is configured with `--enable-poll-insertion`. The backend never uses `btr` or
BMI `andn`, and it rebuilds `~(1 << bit)` with three instructions each time. A C compiler
would use one or two.

Probe (ii), `probe/vor.ml`: `dst |= src` over 64KB of Bytes, 20,000 times.

| Variant | Loop body | Instr/iter | GB/s |
|---|---|---|---|
| or64 | `movq; movq; orq; movq` | 11 | 8.6 |
| or128 | `vmovupd xmm ×2; vorps; vmovupd` | 11 | 19.9 |
| or256 | `vmovupd ymm ×2; vorps; vmovupd` | 11 | 24.1 |

Each loop also has the tagged-index `movq; sarq`, the poll and the compare. All three are
free of allocation and calls. The vectors stay in registers even though the externals use
the boxed types `int64x2`/`int64x4`.

Probe (iii), `probe/domains.ml`: see 2d. Its sieve loop compiles to the same 19 instructions
as the "unsafe" variant.

## What this means for a solution

- Write the hot loop with `%caml_bytes_get64u`/`set64u` (or the `_indexed_by_int64#` forms
  with an `int64#` counter), never `Bytes.get_int64_le`.
- Use 256-bit `int64x4` with `%caml_bytes_getu256u` for pattern ORs (wheel or small-prime
  presieve). Ship `builtin_stubs.c` next to the `.ml`, or depend on `ocaml_simd`.
- AVX2 is the ceiling. AVX-512 is not usable in this release.
- For the multithreaded category, use `Domain.Safe.spawn` with `@ portable` functions and
  `@@ portable` externals, or the plain `Domain.spawn` with the alerts silenced.
