(* Dense copy loops, portable version: 32-bit words through the unboxed bytes primitives.
   build.sh uses this on every architecture other than x86-64.

   The loops use 32-bit loads and stores, two per 64-bit word of the sieve. On Arm, OCaml 5
   puts a `dmb ishld` barrier before every 64-bit integer store to a Bytes buffer (part of
   its memory model); the 32-bit stores do not get it. Little-endian targets only: the two
   halves of a 64-bit word are its low and high 32 bits, so the bit layout is the same as the
   64-bit word view used elsewhere.

   Each function walks [runs] runs of [rb] bytes (rb is 32p for odd p, a multiple of 32),
   starting at byte [base] of [b], and returns the byte offset after the last run. *)

external get32 : Bytes.t -> int -> int32 = "%caml_bytes_get32u"
external set32 : Bytes.t -> int -> int32 -> unit = "%caml_bytes_set32u"

let kind = "scalar"

(* The pattern of one run of four periods (32p bytes) for odd factor p, in [pat]: 32-bit
   word t lsr 5 of the run gets bit t land 31 for each multiple p(2j + 1), at bit
   t = p/2 + jp, j = 0..255. On a little-endian machine that is bit t land 63 of 64-bit word
   t lsr 6. One single-bit OR per composite. *)
let build_pattern pat p =
  Bytes.fill pat 0 (p * 32) '\000';
  for j = 0 to 255 do
    let t = (p lsr 1) + (j * p) in
    let a = (t lsr 5) * 4 in
    set32 pat a (Int32.logor (get32 pat a) (Int32.shift_left 1l (t land 31)))
  done

(* Stores the pattern without reading the sieve: the first factor's pass, which initialises
   the buffer. Eight 32-bit stores (32 bytes) per step. *)
let[@inline] store_runs b pat base runs rb =
  let base = ref base in
  for _ = 1 to runs do
    let q = !base in
    let v = ref 0 in
    while !v < rb do
      let a = q + !v and v0 = !v in
      set32 b a (get32 pat v0);
      set32 b (a + 4) (get32 pat (v0 + 4));
      set32 b (a + 8) (get32 pat (v0 + 8));
      set32 b (a + 12) (get32 pat (v0 + 12));
      set32 b (a + 16) (get32 pat (v0 + 16));
      set32 b (a + 20) (get32 pat (v0 + 20));
      set32 b (a + 24) (get32 pat (v0 + 24));
      set32 b (a + 28) (get32 pat (v0 + 28));
      v := v0 + 32
    done;
    base := q + rb
  done;
  !base

(* ORs the pattern into the sieve, eight 32-bit words (32 bytes) per step. *)
let[@inline] or_runs b pat base runs rb =
  let base = ref base in
  for _ = 1 to runs do
    let q = !base in
    let v = ref 0 in
    while !v < rb do
      let a = q + !v and v0 = !v in
      set32 b a (Int32.logor (get32 b a) (get32 pat v0));
      set32 b (a + 4) (Int32.logor (get32 b (a + 4)) (get32 pat (v0 + 4)));
      set32 b (a + 8) (Int32.logor (get32 b (a + 8)) (get32 pat (v0 + 8)));
      set32 b (a + 12) (Int32.logor (get32 b (a + 12)) (get32 pat (v0 + 12)));
      set32 b (a + 16) (Int32.logor (get32 b (a + 16)) (get32 pat (v0 + 16)));
      set32 b (a + 20) (Int32.logor (get32 b (a + 20)) (get32 pat (v0 + 20)));
      set32 b (a + 24) (Int32.logor (get32 b (a + 24)) (get32 pat (v0 + 24)));
      set32 b (a + 28) (Int32.logor (get32 b (a + 28)) (get32 pat (v0 + 28)));
      v := v0 + 32
    done;
    base := q + rb
  done;
  !base
