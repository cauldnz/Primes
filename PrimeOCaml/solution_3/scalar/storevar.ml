(* ox-020 diagnostic only: store-primitive variants of the dense copy loop (Dense.store_runs),
   to find a 64-bit store that the Arm backend emits without the OCaml 5 memory-model barrier
   (dmb ishld before a store to mutable memory). Each copy_<name> copies a pattern of [rb]
   bytes (a multiple of 32) [runs] times into a buffer, four words per step like store_runs.
   The Dockerfile compiles this file with -S so primes.ml can print each loop's assembly;
   primes.ml times each variant with [bench]. Not used by the sieve. *)

open Bigarray

type ba64 = (int64, int64_elt, c_layout) Array1.t
type bstr = (char, int8_unsigned_elt, c_layout) Array1.t

external get64 : Bytes.t -> int -> int64 = "%caml_bytes_get64u"
external set64 : Bytes.t -> int -> int64 -> unit = "%caml_bytes_set64u"
external get64h : Bytes.t -> int -> int64# = "%caml_bytes_get64u#"
external set64h : Bytes.t -> int -> int64# -> unit = "%caml_bytes_set64u#"
external get64ix : Bytes.t -> int64# -> int64# = "%caml_bytes_get64u#_indexed_by_int64#"
external set64ix : Bytes.t -> int64# -> int64# -> unit = "%caml_bytes_set64u#_indexed_by_int64#"
external bs_get64 : bstr -> int -> int64 = "%caml_bigstring_get64u"
external bs_set64 : bstr -> int -> int64 -> unit = "%caml_bigstring_set64u"
external get32 : Bytes.t -> int -> int32 = "%caml_bytes_get32u"
external set32 : Bytes.t -> int -> int32 -> unit = "%caml_bytes_set32u"
external unbox : int64 -> int64# = "%unbox_int64"
external box : int64# -> int64 = "%box_int64"
external aget : ('a : any mod separable). 'a array -> int -> 'a = "%array_unsafe_get"
  [@@layout_poly]
external aset : ('a : any mod separable). 'a array -> int -> 'a -> unit = "%array_unsafe_set"
  [@@layout_poly]
external amake : ('a : any mod separable). int -> 'a -> 'a array = "%makearray_dynamic"
  [@@layout_poly]

(* a. current: boxed-int64 bytes primitive *)
let[@inline never] copy_set64 b pat rb runs =
  let base = ref 0 in
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
  done

(* b1. unboxed int64# bytes primitive, int index *)
let[@inline never] copy_set64h b pat rb runs =
  let base = ref 0 in
  for _ = 1 to runs do
    let q = !base in
    let v = ref 0 in
    while !v < rb do
      let a = q + !v and v0 = !v in
      set64h b a (get64h pat v0);
      set64h b (a + 8) (get64h pat (v0 + 8));
      set64h b (a + 16) (get64h pat (v0 + 16));
      set64h b (a + 24) (get64h pat (v0 + 24));
      v := v0 + 32
    done;
    base := q + rb
  done

(* b2. unboxed int64# bytes primitive indexed by int64# *)
let[@inline never] copy_set64ix b pat rb runs =
  let base = ref 0 in
  for _ = 1 to runs do
    let q = !base in
    let v = ref 0 in
    while !v < rb do
      let a = q + !v and v0 = !v in
      let ix x = unbox (Int64.of_int x) in
      set64ix b (ix a) (get64ix pat (ix v0));
      set64ix b (ix (a + 8)) (get64ix pat (ix (v0 + 8)));
      set64ix b (ix (a + 16)) (get64ix pat (ix (v0 + 16)));
      set64ix b (ix (a + 24)) (get64ix pat (ix (v0 + 24)));
      v := v0 + 32
    done;
    base := q + rb
  done

(* c. int64 Bigarray, word indices *)
let[@inline never] copy_ba64 (b : ba64) (pat : ba64) rb runs =
  let rw = rb / 8 in
  let base = ref 0 in
  for _ = 1 to runs do
    let q = !base in
    let v = ref 0 in
    while !v < rw do
      let a = q + !v and v0 = !v in
      Array1.unsafe_set b a (Array1.unsafe_get pat v0);
      Array1.unsafe_set b (a + 1) (Array1.unsafe_get pat (v0 + 1));
      Array1.unsafe_set b (a + 2) (Array1.unsafe_get pat (v0 + 2));
      Array1.unsafe_set b (a + 3) (Array1.unsafe_get pat (v0 + 3));
      v := v0 + 4
    done;
    base := q + rw
  done

(* d. char Bigarray (bigstring) 64-bit primitive *)
let[@inline never] copy_bs64 (b : bstr) (pat : bstr) rb runs =
  let base = ref 0 in
  for _ = 1 to runs do
    let q = !base in
    let v = ref 0 in
    while !v < rb do
      let a = q + !v and v0 = !v in
      bs_set64 b a (bs_get64 pat v0);
      bs_set64 b (a + 8) (bs_get64 pat (v0 + 8));
      bs_set64 b (a + 16) (bs_get64 pat (v0 + 16));
      bs_set64 b (a + 24) (bs_get64 pat (v0 + 24));
      v := v0 + 32
    done;
    base := q + rb
  done

(* e. byte stores, eight per step (reference) *)
let[@inline never] copy_bytes8 b pat rb runs =
  let base = ref 0 in
  for _ = 1 to runs do
    let q = !base in
    let v = ref 0 in
    while !v < rb do
      let a = q + !v and v0 = !v in
      Bytes.unsafe_set b a (Bytes.unsafe_get pat v0);
      Bytes.unsafe_set b (a + 1) (Bytes.unsafe_get pat (v0 + 1));
      Bytes.unsafe_set b (a + 2) (Bytes.unsafe_get pat (v0 + 2));
      Bytes.unsafe_set b (a + 3) (Bytes.unsafe_get pat (v0 + 3));
      Bytes.unsafe_set b (a + 4) (Bytes.unsafe_get pat (v0 + 4));
      Bytes.unsafe_set b (a + 5) (Bytes.unsafe_get pat (v0 + 5));
      Bytes.unsafe_set b (a + 6) (Bytes.unsafe_get pat (v0 + 6));
      Bytes.unsafe_set b (a + 7) (Bytes.unsafe_get pat (v0 + 7));
      v := v0 + 8
    done;
    base := q + rb
  done

(* f. 32-bit stores, two per word *)
let[@inline never] copy_set32 b pat rb runs =
  let base = ref 0 in
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
  done

(* g1. unboxed int64# array, word indices *)
let[@inline never] copy_arr64h (b : int64# array) (pat : int64# array) rb runs =
  let rw = rb / 8 in
  let base = ref 0 in
  for _ = 1 to runs do
    let q = !base in
    let v = ref 0 in
    while !v < rw do
      let a = q + !v and v0 = !v in
      aset b a (aget pat v0);
      aset b (a + 1) (aget pat (v0 + 1));
      aset b (a + 2) (aget pat (v0 + 2));
      aset b (a + 3) (aget pat (v0 + 3));
      v := v0 + 4
    done;
    base := q + rw
  done

(* g2. flat float array (64-bit floating-point stores), word indices *)
let[@inline never] copy_farr (b : float array) (pat : float array) rb runs =
  let rw = rb / 8 in
  let base = ref 0 in
  for _ = 1 to runs do
    let q = !base in
    let v = ref 0 in
    while !v < rw do
      let a = q + !v and v0 = !v in
      Array.unsafe_set b a (Array.unsafe_get pat v0);
      Array.unsafe_set b (a + 1) (Array.unsafe_get pat (v0 + 1));
      Array.unsafe_set b (a + 2) (Array.unsafe_get pat (v0 + 2));
      Array.unsafe_set b (a + 3) (Array.unsafe_get pat (v0 + 3));
      v := v0 + 4
    done;
    base := q + rw
  done

(* g3. the bytes buffer viewed as a float array: 64-bit floating-point stores into the same
   Bytes the sieve uses, pattern words read as int64 and moved bitwise to a float register *)
let[@inline never] copy_magicf b pat rb runs =
  let f : float array = Obj.magic b in
  let rw = rb / 8 in
  let base = ref 0 in
  for _ = 1 to runs do
    let q = !base in
    let v = ref 0 in
    while !v < rw do
      let a = q + !v and v0 = !v in
      let w i = Int64.float_of_bits (get64 pat (8 * i)) in
      Array.unsafe_set f a (w v0);
      Array.unsafe_set f (a + 1) (w (v0 + 1));
      Array.unsafe_set f (a + 2) (w (v0 + 2));
      Array.unsafe_set f (a + 3) (w (v0 + 3));
      v := v0 + 4
    done;
    base := q + rw
  done

(* Runs each variant [reps] times copying a [pat_words]-word pattern into a [buf_bytes]
   buffer (as many whole patterns as fit), checks the copy, and calls
   [report name ns_per_copy ok]. [clock] returns nanoseconds. *)
let bench ~clock ~report ~pat_words ~buf_bytes ~reps =
  let rb = pat_words * 8 in
  let runs = buf_bytes / rb in
  let n = runs * rb in
  let nw = n / 8 in
  let pat = Bytes.create rb in
  let seed = ref 0x9E3779B97F4A7C15L in
  for i = 0 to pat_words - 1 do
    seed := Int64.add (Int64.mul !seed 6364136223846793005L) 1442695040888963407L;
    set64 pat (8 * i) !seed
  done;
  let expect i = get64 pat (8 * (i mod pat_words)) in
  let time name f check =
    f ();
    let t0 = clock () in
    for _ = 1 to reps do f () done;
    let t1 = clock () in
    let ok = ref true in
    for i = 0 to nw - 1 do if check i <> expect i then ok := false done;
    report name (float (t1 - t0) /. float reps) !ok
  in
  let fresh () = Bytes.make n '\000' in
  (let b = fresh () in time "set64" (fun () -> copy_set64 b pat rb runs) (fun i -> get64 b (8 * i)));
  (let b = fresh () in time "set64h" (fun () -> copy_set64h b pat rb runs) (fun i -> get64 b (8 * i)));
  (let b = fresh () in time "set64ix" (fun () -> copy_set64ix b pat rb runs) (fun i -> get64 b (8 * i)));
  (let b : ba64 = Array1.create int64 c_layout nw and p : ba64 = Array1.create int64 c_layout pat_words in
   Array1.fill b 0L;
   for i = 0 to pat_words - 1 do Array1.unsafe_set p i (expect i) done;
   time "ba64" (fun () -> copy_ba64 b p rb runs) (fun i -> Array1.unsafe_get b i));
  (let b : bstr = Array1.create char c_layout n and p : bstr = Array1.create char c_layout rb in
   Array1.fill b '\000';
   for i = 0 to rb - 1 do Array1.unsafe_set p i (Bytes.get pat i) done;
   time "bs64" (fun () -> copy_bs64 b p rb runs) (fun i -> bs_get64 b (8 * i)));
  (let b = fresh () in time "bytes8" (fun () -> copy_bytes8 b pat rb runs) (fun i -> get64 b (8 * i)));
  (let b = fresh () in time "set32" (fun () -> copy_set32 b pat rb runs) (fun i -> get64 b (8 * i)));
  (let b : int64# array = amake nw #0L and p : int64# array = amake pat_words #0L in
   for i = 0 to pat_words - 1 do aset p i (unbox (expect i)) done;
   time "arr64h" (fun () -> copy_arr64h b p rb runs)
     (fun i -> box (aget b i)));
  (let b = Array.make nw 0.0 and p = Array.init pat_words (fun i -> Int64.float_of_bits (expect i)) in
   time "farr" (fun () -> copy_farr b p rb runs) (fun i -> Int64.bits_of_float (Array.unsafe_get b i)));
  (let b = fresh () in time "magicf" (fun () -> copy_magicf b pat rb runs) (fun i -> get64 b (8 * i)))
