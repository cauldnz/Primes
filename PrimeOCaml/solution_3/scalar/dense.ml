(* Dense copy loops, portable version: 64-bit words through the unboxed bytes primitives.
   build.sh uses this on every architecture other than x86-64.

   Each function walks [runs] runs of [rb] bytes (rb is 32p for odd p, a multiple of 32),
   starting at byte [base] of [b], and returns the byte offset after the last run. *)

external get64 : Bytes.t -> int -> int64 = "%caml_bytes_get64u"
external set64 : Bytes.t -> int -> int64 -> unit = "%caml_bytes_set64u"

let kind = "scalar"

(* Stores the pattern without reading the sieve: the first factor's pass, which initialises
   the buffer. *)
let[@inline] store_runs b pat base runs rb =
  let base = ref base in
  for _ = 1 to runs do
    let q = !base in
    let v = ref 0 in
    while !v < rb do
      let a = q + !v and v0 = !v in
      set64 b a (get64 pat v0);
      set64 b (a + 8) (get64 pat (v0 + 8));
      set64 b (a + 16) (get64 pat (v0 + 16));
      set64 b (a + 24) (get64 pat (v0 + 24));
      v := v0 + 32
    done;
    base := q + rb
  done;
  !base

(* ORs the pattern into the sieve. Two runs per step: each pattern word is loaded once and ORed
   into the same word of two consecutive runs, eight sieve words a step. An odd run left over
   goes through the one-run loop, four words a step. *)
let[@inline] or_runs b pat base runs rb =
  let base = ref base in
  for _ = 1 to runs / 2 do
    let q = !base in
    let v = ref 0 in
    while !v < rb do
      let a = q + !v and v0 = !v in
      let a2 = a + rb in
      let w0 = get64 pat v0 and w1 = get64 pat (v0 + 8)
      and w2 = get64 pat (v0 + 16) and w3 = get64 pat (v0 + 24) in
      set64 b a (Int64.logor (get64 b a) w0);
      set64 b (a + 8) (Int64.logor (get64 b (a + 8)) w1);
      set64 b (a + 16) (Int64.logor (get64 b (a + 16)) w2);
      set64 b (a + 24) (Int64.logor (get64 b (a + 24)) w3);
      set64 b a2 (Int64.logor (get64 b a2) w0);
      set64 b (a2 + 8) (Int64.logor (get64 b (a2 + 8)) w1);
      set64 b (a2 + 16) (Int64.logor (get64 b (a2 + 16)) w2);
      set64 b (a2 + 24) (Int64.logor (get64 b (a2 + 24)) w3);
      v := v0 + 32
    done;
    base := q + (2 * rb)
  done;
  if runs land 1 = 1 then begin
    let q = !base in
    let v = ref 0 in
    while !v < rb do
      let a = q + !v and v0 = !v in
      set64 b a (Int64.logor (get64 b a) (get64 pat v0));
      set64 b (a + 8) (Int64.logor (get64 b (a + 8)) (get64 pat (v0 + 8)));
      set64 b (a + 16) (Int64.logor (get64 b (a + 16)) (get64 pat (v0 + 16)));
      set64 b (a + 24) (Int64.logor (get64 b (a + 24)) (get64 pat (v0 + 24)));
      v := v0 + 32
    done;
    base := q + rb
  end;
  !base
