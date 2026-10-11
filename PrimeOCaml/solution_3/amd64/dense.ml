(* Dense copy loops, x86-64 version: one 256-bit AVX load, OR and store per step, through
   OxCaml's SIMD vector types. build.sh uses this on x86-64 only. OxCaml targets AVX2 by
   default there.

   Each function walks [runs] runs of [rb] bytes (rb is 32p for odd p, a multiple of 32),
   starting at byte [base] of [b], and returns the byte offset after the last run. *)

(* Unaligned 256-bit load and store on a Bytes buffer, without bounds checks. The byte offset
   is an untagged 64-bit integer (int64#), so the address is one add away. A tagged int
   offset costs two extra shifts per step to strip the tag. *)
external get256 : Bytes.t -> int64# -> int64x4 = "%caml_bytes_getu256u_indexed_by_int64#"
external set256 : Bytes.t -> int64# -> int64x4 -> unit
  = "%caml_bytes_setu256u_indexed_by_int64#"

(* vpor/vorps. A compiler builtin: ocamlopt emits the instruction inline. The C names exist
   only for the linker (simd_stubs.c). *)
external vor : int64x4 -> int64x4 -> int64x4
  = "caml_vec256_unreachable" "caml_avx_vec256_or"
  [@@noalloc] [@@unboxed] [@@builtin]

(* int64# conversions and arithmetic. flambda2 removes the boxes. *)
external box : int64# -> int64 = "%box_int64"
external unbox : int64 -> int64# = "%unbox_int64"

let[@inline always] u x = unbox (Int64.of_int x)
let[@inline always] add x y = unbox (Int64.add (box x) (box y))
let[@inline always] lt x y = Int64.compare (box x) (box y) < 0

let kind = "avx"

(* Stores the pattern without reading the sieve: the first factor's pass, which initialises
   the buffer. [a] walks the sieve, [v] the pattern. *)
let[@inline] store_runs b pat base runs rb =
  let rb = u rb in
  let mutable a = u base in
  for _ = 1 to runs do
    let e = add a rb in
    let mutable v = #0L in
    while lt a e do
      set256 b a (get256 pat v);
      a <- add a #32L;
      v <- add v #32L
    done
  done;
  Int64.to_int (box a)

(* ORs the pattern into the sieve, 32 bytes per step. Four consecutive runs per pass of the
   loop: each pattern vector is loaded once and ORed into the same offset of all four runs,
   which are rb bytes apart. Each sieve word still gets its own load, OR and store. Leftover
   runs (runs mod 4) take the two-run loop and then the one-run loop. *)
let[@inline] or_runs b pat base runs rb =
  let rb = u rb in
  let mutable a = u base in
  for _ = 1 to runs / 4 do
    let e = add a rb in
    let mutable v = #0L in
    while lt a e do
      let x = get256 pat v in
      let a2 = add a rb in
      let a3 = add a2 rb in
      let a4 = add a3 rb in
      set256 b a (vor (get256 b a) x);
      set256 b a2 (vor (get256 b a2) x);
      set256 b a3 (vor (get256 b a3) x);
      set256 b a4 (vor (get256 b a4) x);
      a <- add a #32L;
      v <- add v #32L
    done;
    a <- add a (add rb (add rb rb))
  done;
  if runs land 2 = 2 then begin
    let e = add a rb in
    let mutable v = #0L in
    while lt a e do
      let x = get256 pat v in
      let a2 = add a rb in
      set256 b a (vor (get256 b a) x);
      set256 b a2 (vor (get256 b a2) x);
      a <- add a #32L;
      v <- add v #32L
    done;
    a <- add a rb
  end;
  if runs land 1 = 1 then begin
    let e = add a rb in
    let mutable v = #0L in
    while lt a e do
      set256 b a (vor (get256 b a) (get256 pat v));
      a <- add a #32L;
      v <- add v #32L
    done
  end;
  Int64.to_int (box a)
