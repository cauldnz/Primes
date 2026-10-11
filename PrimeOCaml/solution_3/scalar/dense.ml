(* Dense copy loops, portable version: 64-bit words through the unboxed bytes primitives.
   build.sh uses this on every architecture other than x86-64.

   Each function walks [runs] runs of [rb] bytes (rb is 32p for odd p, a multiple of 32),
   starting at byte [base] of [b], and returns the byte offset after the last run. *)

(* Unchecked 64-bit loads and stores with the byte offset and the word as untagged 64-bit
   integers (int64#), so the address is one add away. A tagged int offset costs shifts to strip
   the tag. These primitives are not tied to x86-64. *)
external get64 : Bytes.t -> int64# -> int64# = "%caml_bytes_get64u#_indexed_by_int64#"
external set64 : Bytes.t -> int64# -> int64# -> unit = "%caml_bytes_set64u#_indexed_by_int64#"
external box : int64# -> int64 = "%box_int64"
external unbox : int64 -> int64# = "%unbox_int64"

let[@inline always] u x = unbox (Int64.of_int x)
let[@inline always] add x y = unbox (Int64.add (box x) (box y))
let[@inline always] lt x y = Int64.compare (box x) (box y) < 0
let[@inline always] vor x y = unbox (Int64.logor (box x) (box y))

let kind = "scalar"

(* Stores the pattern without reading the sieve: the first factor's pass, which initialises
   the buffer. [a] walks the sieve, [v] the pattern. *)
let[@inline] store_runs b pat base runs rb =
  let rb = u rb in
  let mutable a = u base in
  for _ = 1 to runs do
    let e = add a rb in
    let mutable v = #0L in
    while lt a e do
      set64 b a (get64 pat v);
      set64 b (add a #8L) (get64 pat (add v #8L));
      set64 b (add a #16L) (get64 pat (add v #16L));
      set64 b (add a #24L) (get64 pat (add v #24L));
      a <- add a #32L;
      v <- add v #32L
    done
  done;
  Int64.to_int (box a)

(* ORs the pattern into the sieve, four words per step. *)
let[@inline] or_runs b pat base runs rb =
  let rb = u rb in
  let mutable a = u base in
  for _ = 1 to runs do
    let e = add a rb in
    let mutable v = #0L in
    while lt a e do
      set64 b a (vor (get64 b a) (get64 pat v));
      set64 b (add a #8L) (vor (get64 b (add a #8L)) (get64 pat (add v #8L)));
      set64 b (add a #16L) (vor (get64 b (add a #16L)) (get64 pat (add v #16L)));
      set64 b (add a #24L) (vor (get64 b (add a #24L)) (get64 pat (add v #24L)));
      a <- add a #32L;
      v <- add v #32L
    done
  done;
  Int64.to_int (box a)
