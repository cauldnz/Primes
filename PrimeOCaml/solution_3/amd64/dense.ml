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

(* vpxor, the same kind of builtin. Only used to make a zero vector (x xor x). *)
external vxor : int64x4 -> int64x4 -> int64x4
  = "caml_vec256_unreachable" "caml_avx_vec256_xor"
  [@@noalloc] [@@unboxed] [@@builtin]

(* 64-bit word access with an untagged offset and word, as in sparse.ml. *)
external get64x : Bytes.t -> int64# -> int64# = "%caml_bytes_get64u#_indexed_by_int64#"
external set64x : Bytes.t -> int64# -> int64# -> unit = "%caml_bytes_set64u#_indexed_by_int64#"

(* int64# conversions and arithmetic. flambda2 removes the boxes. *)
external box : int64# -> int64 = "%box_int64"
external unbox : int64 -> int64# = "%unbox_int64"

let[@inline always] u x = unbox (Int64.of_int x)
let[@inline always] add x y = unbox (Int64.add (box x) (box y))
let[@inline always] lt x y = Int64.compare (box x) (box y) < 0

let[@inline always] or_u x y = unbox (Int64.logor (box x) (box y))
let[@inline always] and_u x y = unbox (Int64.logand (box x) (box y))
let[@inline always] shr_u x n = unbox (Int64.shift_right_logical (box x) n)
let[@inline always] shl_u x n = unbox (Int64.shift_left (box x) n)
let[@inline always] to_int x = Int64.to_int (box x)

let kind = "avx"

(* The word pattern of one run of four periods (32p bytes) for odd factor p, in [pat]: word
   t lsr 6 of the run gets bit t land 63 for each multiple p(2j + 1), at bit t = p/2 + jp,
   j = 0..255. The 32p bytes are zeroed with p 256-bit stores, then each multiple is set with
   its own single-bit OR into its 64-bit word: one composite per OR. The bit index t, the word
   offset (t lsr 3) land -8 and the mask are untagged 64-bit integers. *)
let build_pattern pat p =
  let x = get256 pat #0L in
  let z = vxor x x in
  let e = u (p * 32) in
  let mutable a = #0L in
  while lt a e do
    set256 pat a z;
    a <- add a #32L
  done;
  let up = u p in
  let mutable t = u (p lsr 1) in
  for _ = 0 to 255 do
    let w = and_u (shr_u t 3) (u (-8)) in
    set64x pat w (or_u (get64x pat w) (shl_u #1L (to_int (and_u t #63L))));
    t <- add t up
  done

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
