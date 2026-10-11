(* Sparse clearing, x86-64 version: one 64-bit word OR per composite, with untagged offsets.
   build.sh uses this on x86-64 only. On Arm Neoverse N2 this form was 28% slower than the
   byte OR in scalar/sparse.ml, so other architectures keep that one. *)

(* 64-bit accesses with the offset and the word as untagged 64-bit integers (int64#).
   flambda2 removes the boxes in the helpers below. *)
external get64x : Bytes.t -> int64# -> int64# = "%caml_bytes_get64u#_indexed_by_int64#"
external set64x : Bytes.t -> int64# -> int64# -> unit = "%caml_bytes_set64u#_indexed_by_int64#"
external box : int64# -> int64 = "%box_int64"
external unbox : int64 -> int64# = "%unbox_int64"

let[@inline always] u x = unbox (Int64.of_int x)
let[@inline always] add_u x y = unbox (Int64.add (box x) (box y))
let[@inline always] lt_u x y = Int64.compare (box x) (box y) < 0
let[@inline always] or_u x y = unbox (Int64.logor (box x) (box y))

(* The partial last chunk of the sparse clearing, starting at byte [a]: one byte OR per
   composite, stopping at the first offset past the end. A separate function, so that clear
   keeps nothing but its loop values alive across its loop; with the tagged offsets also
   alive, the untagged ones were pushed out of registers. *)
let[@inline never] sparse_tail b p a nbytes =
  let left = nbytes - a in
  let h = p lsr 1 in
  let t = ref h in
  while !t lsr 3 < left && !t < h + (8 * p) do
    let i = a + (!t lsr 3) in
    Bytes.unsafe_set b i
      (Char.unsafe_chr (Char.code (Bytes.unsafe_get b i) lor (1 lsl (!t land 7))));
    t := !t + p
  done

(* Sparse clearing over bytes for odd p >= 128 on the sieve [b] of [nbytes] bytes. Chunks of
   p bytes start at byte multiples of p; in each, the eight multiples p(2j + 1), j = 0..7, sit
   at fixed byte offsets o_j = (p/2 + jp) / 8 with fixed single-bit masks.

   In the whole chunks each composite is one OR of its single-bit mask into the unaligned
   64-bit word that starts at its byte: the mask sits in the low byte (little-endian), so the
   other seven bytes are ORed with zero and do not change. The word stays inside the chunk:
   o_7 <= 15p/16, and p >= 128 gives o_7 + 8 <= p. Offsets, masks and the chunk start are
   untagged 64-bit integers (int64#), so a composite is an add, a load, an OR and a store. OCaml
   has no byte access indexed by an untagged integer; with tagged ints a byte OR costs seven
   instructions (tag shifts on the index and on the byte). The partial last chunk (sparse_tail)
   uses plain byte ORs, so nothing is touched past the end of the sieve. *)
let clear b nbytes p =
  let h = p lsr 1 in
  let o0 = h lsr 3 and m0 = 1 lsl (h land 7) in
  let t = h + p in
  let o1 = t lsr 3 and m1 = 1 lsl (t land 7) in
  let t = t + p in
  let o2 = t lsr 3 and m2 = 1 lsl (t land 7) in
  let t = t + p in
  let o3 = t lsr 3 and m3 = 1 lsl (t land 7) in
  let t = t + p in
  let o4 = t lsr 3 and m4 = 1 lsl (t land 7) in
  let t = t + p in
  let o5 = t lsr 3 and m5 = 1 lsl (t land 7) in
  let t = t + p in
  let o6 = t lsr 3 and m6 = 1 lsl (t land 7) in
  let t = t + p in
  let o7 = t lsr 3 and m7 = 1 lsl (t land 7) in
  let s0 = p * p / 2 / 8 / p * p in
  let chunks = (nbytes - s0) / p in
  let[@inline always] markw a o m =
    let i = add_u a o in
    set64x b i (or_u (get64x b i) m)
  in
  let uo0 = u o0 and um0 = u m0 and uo1 = u o1 and um1 = u m1 in
  let uo2 = u o2 and um2 = u m2 and uo3 = u o3 and um3 = u m3 in
  let uo4 = u o4 and um4 = u m4 and uo5 = u o5 and um5 = u m5 in
  let uo6 = u o6 and um6 = u m6 and uo7 = u o7 and um7 = u m7 in
  let up = u p in
  let qe = u (s0 + (chunks * p)) in
  let mutable q = u s0 in
  while lt_u q qe do
    markw q uo0 um0;  (* one composite each *)
    markw q uo1 um1;
    markw q uo2 um2;
    markw q uo3 um3;
    markw q uo4 um4;
    markw q uo5 um5;
    markw q uo6 um6;
    markw q uo7 um7;
    q <- add_u q up
  done;
  sparse_tail b p (Int64.to_int (box q)) nbytes
