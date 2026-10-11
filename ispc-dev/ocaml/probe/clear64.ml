(* Probe (i): clear bits in a Bytes buffer of 64-bit words.
   Odd-only bit sieve up to 1,000,000 (bit k stands for 2k+1), six ways of
   reading and writing the words. Each variant is run [reps] times and must
   find 78498 primes. *)

let limit = 1_000_000
let nbits = limit / 2
let nwords = (nbits + 63) / 64
let reps = 200

(* Unsafe, boxed-type primitives: no bounds check. flambda2 removes the
   Int64 boxes inside the loop. *)
external get64u : bytes -> int -> int64 = "%caml_bytes_get64u"
external set64u : bytes -> int -> int64 -> unit = "%caml_bytes_set64u"

(* Unsafe primitives returning an unboxed int64# directly. *)
external get64u_u : bytes -> int -> int64# = "%caml_bytes_get64u#"
external set64u_u : bytes -> int -> int64# -> unit = "%caml_bytes_set64u#"
external box : int64# -> int64 = "%box_int64"
external unbox : int64 -> int64# = "%unbox_int64"

(* A: stdlib Bytes.get_int64_le / set_int64_le (bounds checked). *)
let clear_stdlib buf start step =
  let i = ref start in
  while !i < nbits do
    let k = !i in
    let off = (k lsr 6) lsl 3 in
    let w = Bytes.get_int64_le buf off in
    Bytes.set_int64_le buf off
      (Int64.logand w (Int64.lognot (Int64.shift_left 1L (k land 63))));
    i := k + step
  done

(* B: %caml_bytes_get64u / set64u. *)
let clear_unsafe buf start step =
  let i = ref start in
  while !i < nbits do
    let k = !i in
    let off = (k lsr 6) lsl 3 in
    let w = get64u buf off in
    set64u buf off
      (Int64.logand w (Int64.lognot (Int64.shift_left 1L (k land 63))));
    i := k + step
  done

(* C: %caml_bytes_get64u# with int64# in the loop. *)
let clear_unboxed buf start step =
  let i = ref start in
  while !i < nbits do
    let k = !i in
    let off = (k lsr 6) lsl 3 in
    let w = box (get64u_u buf off) in
    set64u_u buf off
      (unbox (Int64.logand w (Int64.lognot (Int64.shift_left 1L (k land 63)))));
    i := k + step
  done

(* D: byte-granular, plain tagged ints only (Bytes.unsafe_get/set). *)
let clear_bytes buf start step =
  let i = ref start in
  while !i < nbits do
    let k = !i in
    let off = k lsr 3 in
    let b = Char.code (Bytes.unsafe_get buf off) in
    Bytes.unsafe_set buf off (Char.unsafe_chr (b land lnot (1 lsl (k land 7))));
    i := k + step
  done

(* E: untagged int# loop counter (primitives from Stdlib_stable.Int_u,
   declared here so no library is needed), mutable local via [let mutable]. *)
external of_int : int -> int# = "%int#_of_int"
external to_int : int# -> int = "%int_of_int#"
external lt_u : int# -> int# -> bool = "%int#_lessthan"
external add_u : int# -> int# -> int# = "%int#_add"
external land_u : int# -> int# -> int# = "%int#_and"
external lsr_u : int# -> int -> int# = "%int#_lsr"
external lsl_u : int# -> int -> int# = "%int#_lsl"

let clear_untagged buf start step =
  let step = of_int step and lim = of_int nbits and m = of_int 63 in
  let mutable i = of_int start in
  while lt_u i lim do
    let off = to_int (lsl_u (lsr_u i 6) 3) in
    let w = get64u buf off in
    set64u buf off
      (Int64.logand w (Int64.lognot (Int64.shift_left 1L (to_int (land_u i m)))));
    i <- add_u i step
  done

(* F: int64# loop counter and int64#-indexed loads (full 64-bit arithmetic,
   so no 63-bit wrap fix-ups). Int64 ops on boxed values are unboxed by
   flambda2; box/unbox only change the type. *)
external get64x : bytes -> int64# -> int64 = "%caml_bytes_get64u_indexed_by_int64#"
external set64x : bytes -> int64# -> int64 -> unit = "%caml_bytes_set64u_indexed_by_int64#"

let clear_int64 buf start step =
  let step = Int64.of_int step and lim = Int64.of_int nbits in
  let mutable i = unbox (Int64.of_int start) in
  while Int64.compare (box i) lim < 0 do
    let k = box i in
    let off = unbox (Int64.shift_left (Int64.shift_right_logical k 6) 3) in
    let w = get64x buf off in
    set64x buf off
      (Int64.logand w
         (Int64.lognot (Int64.shift_left 1L (Int64.to_int (Int64.logand k 63L)))));
    i <- unbox (Int64.add k step)
  done

let is_set buf k =
  Char.code (Bytes.unsafe_get buf (k lsr 3)) land (1 lsl (k land 7)) <> 0

let sieve clear =
  let buf = Bytes.make (nwords * 8) '\xff' in
  let f = ref 1 in               (* bit 1 = number 3 *)
  while (2 * !f + 1) * (2 * !f + 1) <= limit do
    if is_set buf !f then begin
      let p = 2 * !f + 1 in
      clear buf ((p * p) / 2) p
    end;
    incr f
  done;
  buf

let count buf =
  let c = ref 1 in               (* 2 *)
  for k = 1 to nbits - 1 do if is_set buf k then incr c done;
  !c

let run name clear =
  let t0 = Sys.time () in
  let last = ref (Bytes.empty) in
  for _ = 1 to reps do last := sieve clear done;
  let dt = Sys.time () -. t0 in
  let n = count !last in
  Printf.printf "%-8s primes=%d %s  %.3f ms/pass\n" name n
    (if n = 78498 then "ok" else "WRONG") (1000. *. dt /. float reps)

let () =
  for _ = 1 to 2 do
    run "stdlib" clear_stdlib;
    run "unsafe" clear_unsafe;
    run "unboxed" clear_unboxed;
    run "bytes8" clear_bytes;
    run "untagged" clear_untagged;
    run "int64#" clear_int64
  done
