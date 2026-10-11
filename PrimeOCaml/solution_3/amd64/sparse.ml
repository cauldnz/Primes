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
   at fixed byte offsets (p/2 + jp) / 8 and fixed bits (p/2 + jp) land 7. As p is odd, the
   eight bits are all different, so each bit k of a byte holds exactly one of the eight. The
   loop takes them in order of their bit, with byte offset o_k for bit k, and the mask of each
   is the constant 1 lsl k. Only the eight offsets are live in the loop, not eight offsets and
   eight masks.

   In the whole chunks each composite is one OR of its single-bit mask into the unaligned
   64-bit word that starts at its byte: the mask sits in the low byte (little-endian), so the
   other seven bytes are ORed with zero and do not change. The word stays inside the chunk:
   o_k <= 15p/16, and p >= 128 gives o_k + 8 <= p. Offsets and the chunk start are untagged
   64-bit integers (int64#), so a composite is an add, a load, an OR with a constant and a
   store. OCaml has no byte access indexed by an untagged integer; with tagged ints a byte OR
   costs seven instructions (tag shifts on the index and on the byte). The partial last chunk
   (sparse_tail) uses plain byte ORs, so nothing is touched past the end of the sieve.

   The loop takes two whole chunks per iteration (sixteen composites, at q + o_k and
   q + p + o_k), so its add, compare and safepoint poll come once per sixteen ORs; an odd last
   whole chunk is done on its own before the tail. *)
let clear b nbytes p =
  let o0 = ref 0 and o1 = ref 0 and o2 = ref 0 and o3 = ref 0
  and o4 = ref 0 and o5 = ref 0 and o6 = ref 0 and o7 = ref 0 in
  let t = ref (p lsr 1) in
  for _ = 0 to 7 do
    let o = !t lsr 3 in
    (match !t land 7 with
     | 0 -> o0 := o | 1 -> o1 := o | 2 -> o2 := o | 3 -> o3 := o
     | 4 -> o4 := o | 5 -> o5 := o | 6 -> o6 := o | _ -> o7 := o);
    t := !t + p
  done;
  let o0 = u !o0 and o1 = u !o1 and o2 = u !o2 and o3 = u !o3 in
  let o4 = u !o4 and o5 = u !o5 and o6 = u !o6 and o7 = u !o7 in
  let[@inline always] markw a o m =
    let i = add_u a o in
    set64x b i (or_u (get64x b i) (u m))
  in
  let s0 = p * p / 2 / 8 / p * p in
  let chunks = (nbytes - s0) / p in
  let up = u p in
  let qe = u (s0 + ((chunks land (-2)) * p)) in
  let mutable q = u s0 in
  while lt_u q qe do
    markw q o0 1;
    markw q o1 2;
    markw q o2 4;
    markw q o3 8;
    markw q o4 16;
    markw q o5 32;
    markw q o6 64;
    markw q o7 128;
    let q2 = add_u q up in
    markw q2 o0 1;
    markw q2 o1 2;
    markw q2 o2 4;
    markw q2 o3 8;
    markw q2 o4 16;
    markw q2 o5 32;
    markw q2 o6 64;
    markw q2 o7 128;
    q <- add_u q2 up
  done;
  if chunks land 1 = 1 then begin
    markw q o0 1;
    markw q o1 2;
    markw q o2 4;
    markw q o3 8;
    markw q o4 16;
    markw q o5 32;
    markw q o6 64;
    markw q o7 128;
    q <- add_u q up
  end;
  sparse_tail b p (Int64.to_int (box q)) nbytes
