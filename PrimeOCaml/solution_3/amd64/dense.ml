(* Dense copy loops, x86-64 version: one 256-bit AVX load, OR and store per step, through
   OxCaml's SIMD vector types. build.sh uses this on x86-64 only. OxCaml targets AVX2 by
   default there.

   Each function walks [runs] runs of [rb] bytes (rb is 32p for odd p, a multiple of 32),
   starting at byte [base] of [b], and returns the byte offset after the last run. *)

(* Unaligned 256-bit load and store on a Bytes buffer, without bounds checks. *)
external get256 : Bytes.t -> int -> int64x4 = "%caml_bytes_getu256u"
external set256 : Bytes.t -> int -> int64x4 -> unit = "%caml_bytes_setu256u"

(* vpor/vorps. A compiler builtin: ocamlopt emits the instruction inline. The C names exist
   only for the linker (simd_stubs.c). *)
external vor : int64x4 -> int64x4 -> int64x4
  = "caml_vec256_unreachable" "caml_avx_vec256_or"
  [@@noalloc] [@@unboxed] [@@builtin]

let kind = "avx"

(* Stores the pattern without reading the sieve: the first factor's pass, which initialises
   the buffer. *)
let[@inline] store_runs b pat base runs rb =
  let base = ref base in
  for _ = 1 to runs do
    let q = !base in
    let v = ref 0 in
    while !v < rb do
      let v0 = !v in
      set256 b (q + v0) (get256 pat v0);
      v := v0 + 32
    done;
    base := q + rb
  done;
  !base

(* ORs the pattern into the sieve, 32 bytes per step. Two consecutive runs per pass of the
   loop: each pattern vector is loaded once and ORed into the same offset of both runs, which
   are rb bytes apart. Each sieve word still gets its own load, OR and store. With an odd run
   count the last run takes the one-run loop. *)
let[@inline] or_runs b pat base runs rb =
  let base = ref base in
  for _ = 1 to runs / 2 do
    let q = !base in
    let v = ref 0 in
    while !v < rb do
      let v0 = !v in
      let x = get256 pat v0 in
      let a = q + v0 in
      let a2 = a + rb in
      set256 b a (vor (get256 b a) x);
      set256 b a2 (vor (get256 b a2) x);
      v := v0 + 32
    done;
    base := q + (2 * rb)
  done;
  if runs land 1 = 1 then begin
    let q = !base in
    let v = ref 0 in
    while !v < rb do
      let v0 = !v in
      let a = q + v0 in
      set256 b a (vor (get256 b a) (get256 pat v0));
      v := v0 + 32
    done;
    base := q + rb
  end;
  !base
