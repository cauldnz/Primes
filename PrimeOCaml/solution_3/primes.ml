(* Prime sieve drag race: an OxCaml base-algorithm solution by cauldnz.

   The base algorithm: an outer loop finds the next prime, then clears every one of its odd
   multiples individually. Bit i of the sieve stands for the odd number 2i + 1; a set bit means
   composite.

   This is the design of the author's ISPC base entry (PrimeISPC/solution_2) and its Rust port
   (PrimeRust/solution_9), in OCaml built with the OxCaml compiler (5.2.0+ox, flambda2):

   - Dense (factor below 128): the odd multiples of p repeat with a period of p 64-bit words.
     For each factor the sieve builds the word pattern of four periods (4p words) in its own
     scratch buffer, setting each of their 256 multiples with its own single-bit OR, then ORs
     the pattern into the sieve. The copy loops live in module Dense, picked by build.sh: on
     x86-64 (amd64/dense.ml) they use OxCaml's 256-bit vector type and do one AVX load, OR and
     store per 32 bytes; elsewhere (scalar/dense.ml) they do four 64-bit words per step.
   - Sparse (larger factors): eight multiples repeat every p bytes, each at a fixed bit. The
     byte offsets and masks are computed per factor; each composite is one OR of a
     single-bit mask.

   The sieve is a [Bytes] buffer read and written as 64-bit little-endian words or as bytes.
   The 64-bit accesses go through the compiler's unboxed primitives, so the inner loops do not
   allocate. *)

external get64 : Bytes.t -> int -> int64 = "%caml_bytes_get64u"
external set64 : Bytes.t -> int -> int64 -> unit = "%caml_bytes_set64u"

(* The same accesses with the offset and the word as untagged 64-bit integers (int64#), for
   the sparse loop. flambda2 removes the boxes in the helpers below. *)
external get64x : Bytes.t -> int64# -> int64# = "%caml_bytes_get64u#_indexed_by_int64#"
external set64x : Bytes.t -> int64# -> int64# -> unit = "%caml_bytes_set64u#_indexed_by_int64#"
external box : int64# -> int64 = "%box_int64"
external unbox : int64 -> int64# = "%unbox_int64"

let[@inline always] u x = unbox (Int64.of_int x)
let[@inline always] add_u x y = unbox (Int64.add (box x) (box y))
let[@inline always] lt_u x y = Int64.compare (box x) (box y) < 0
let[@inline always] or_u x y = unbox (Int64.logor (box x) (box y))

let sieve_size = 1_000_000
let expected = 78_498
let run_time = 5.0
let label = "cauldnz-oxcaml-base"
let tags = "algorithm=base,faithful=yes,bits=1"

(* Factors below this use the dense resetter, larger ones the sparse one. *)
let dense_limit = 128

(* All of one sieve's state. A new one is created, and its buffers allocated, for every pass. *)
type sieve = {
  size : int;
  nbits : int;  (* one bit per odd number 1, 3, 5, ... up to size *)
  nwords : int;
  bits : Bytes.t;  (* nwords 64-bit words, little-endian *)
  pattern : Bytes.t;  (* scratch for one dense run of four periods *)
}

let create size =
  let nbits = (size + 1) / 2 in
  let nwords = max 1 ((nbits + 63) / 64) in
  (* Not zeroed. Only word 0 is cleared here, so the scan can read the bit for 3. The first
     factor the scan finds is always 3, and its dense pass writes every word without reading
     it, so the rest of the buffer is initialised there. No word is read before it is
     written. *)
  let bits = Bytes.create (nwords * 8) in
  set64 bits 0 0L;
  { size; nbits; nwords; bits; pattern = Bytes.create (dense_limit * 32) }

let[@inline always] is_composite s i =
  (Char.code (Bytes.unsafe_get s.bits (i lsr 3)) lsr (i land 7)) land 1 <> 0

(* The word pattern of one run of four periods (4p words) for odd factor p: word t lsr 6 of
   the run gets bit t land 63 for each multiple p(2j + 1), at bit t = p/2 + jp, j = 0..255.
   One single-bit OR per composite. *)
let build_pattern s p =
  let pat = s.pattern in
  Bytes.fill pat 0 (p * 32) '\000';
  for j = 0 to 255 do
    let t = (p lsr 1) + (j * p) in
    let a = (t lsr 6) * 8 in
    set64 pat a (Int64.logor (get64 pat a) (Int64.shift_left 1L (t land 63)))
  done

(* Dense clearing for odd p < dense_limit. Periods of p words start at word multiples of p;
   clearing starts at the period holding p². The smaller multiples in that period are
   composite too, except p itself, which is restored at the end. Dense walks the whole runs of
   four periods (32p bytes each); the last, partial run takes as many words of the pattern as
   fit. With [init] (the first factor, 3) every word is stored without being loaded, which
   initialises the buffer. *)
let clear_dense s p init =
  build_pattern s p;
  let b = s.bits and pat = s.pattern and n = s.nwords in
  let c0 = p * p / 2 / 64 / p * p in
  let runs = (n - c0) / (4 * p) in
  let rb = p * 32 in
  let q =
    if init then Dense.store_runs b pat (c0 * 8) runs rb
    else Dense.or_runs b pat (c0 * 8) runs rb
  in
  (* The partial last run: fewer than 4p words. *)
  let left = (n * 8) - q in
  let v = ref 0 in
  while !v < left do
    let a = q + !v in
    let x = if init then 0L else get64 b a in
    set64 b a (Int64.logor x (get64 pat !v));
    v := !v + 8
  done;
  (* p itself is prime. *)
  let f = p lsr 1 in
  let i = f lsr 3 in
  Bytes.unsafe_set b i
    (Char.unsafe_chr (Char.code (Bytes.unsafe_get b i) land lnot (1 lsl (f land 7))))

(* The partial last chunk of the sparse clearing, starting at byte [a]: one byte OR per
   composite, stopping at the first offset past the end. A separate function, so that clear_sparse
   keeps nothing but its loop values alive across its loop; with the tagged offsets also alive,
   the untagged ones were pushed out of registers. *)
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

(* Sparse clearing over bytes for odd p >= dense_limit. Chunks of p bytes start at byte
   multiples of p; in each, the eight multiples p(2j + 1), j = 0..7, sit at fixed byte offsets
   o_j = (p/2 + jp) / 8 with fixed single-bit masks.

   In the whole chunks each composite is one OR of its single-bit mask into the unaligned
   64-bit word that starts at its byte: the mask sits in the low byte (little-endian), so the
   other seven bytes are ORed with zero and do not change. The word stays inside the chunk:
   o_7 <= 15p/16, and p >= 128 gives o_7 + 8 <= p. Offsets, masks and the chunk start are
   untagged 64-bit integers (int64#), so a composite is an add, a load, an OR and a store. OCaml
   has no byte access indexed by an untagged integer; with tagged ints a byte OR costs seven
   instructions (tag shifts on the index and on the byte). The partial last chunk (sparse_tail)
   uses plain byte ORs, so nothing is touched past the end of the sieve. *)
let clear_sparse s p =
  let b = s.bits and nbytes = s.nwords * 8 in
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

(* The base algorithm: find the next prime, clear its multiples, repeat up to sqrt(size). *)
let run s =
  let q = ref (int_of_float (sqrt (float_of_int s.size))) in
  while (!q + 1) * (!q + 1) <= s.size do incr q done;
  while !q * !q > s.size do decr q done;
  let q = !q in
  let factor = ref 3 in
  let continue = ref true in
  while !continue && !factor <= q do
    let i = ref (!factor lsr 1) in
    while !i < s.nbits && is_composite s !i do incr i done;  (* next prime *)
    let p = (2 * !i) + 1 in
    if p > q then continue := false
    else begin
      (* 3 is always the first factor: its pass initialises the buffer. *)
      if p < dense_limit then clear_dense s p (p = 3) else clear_sparse s p;
      factor := p + 2
    end
  done

(* Primes up to and including size: unmarked odd numbers from 3, plus 2. *)
let count_primes s =
  if s.size < 2 then 0
  else begin
    let c = ref 1 in
    for i = 1 to s.nbits - 1 do
      if not (is_composite s i) then incr c
    done;
    !c
  end

let sieve_count size =
  let s = create size in
  run s;
  count_primes s

(* Passes completed before the deadline, and the prime count from the first pass. *)
let worker deadline =
  let passes = ref 0 and count = ref 0 in
  while Unix.gettimeofday () < deadline do
    let s = create sieve_size in
    run s;
    if !passes = 0 then count := count_primes s;
    incr passes
  done;
  (!passes, !count)

(* One timed run on [threads] domains, each running its own sieves. Returns false if any
   domain got a wrong count. *)
let timed_run threads =
  let start = Unix.gettimeofday () in
  let deadline = start +. run_time in
  let results =
    if threads = 1 then [ worker deadline ]
    else begin
      (* Each pass allocates a 62.5KB sieve and drops it, while almost nothing stays live. With
         the default space overhead (80) the major GC finishes a cycle every few passes, and
         each cycle stops every domain. Raising it to 1,000 for the multi-domain runs makes
         cycles rare: on a shared 4-vCPU container the 4-domain run went from 15,000-17,000
         passes to 18,000-25,000. The one-domain run keeps the default; with 1,000 it was about
         10% slower, as each new sieve lands in memory that is no longer in cache. *)
      Gc.set { (Gc.get ()) with space_overhead = 1000 };
      List.init threads (fun _ -> Domain.spawn (fun () -> worker deadline))
      |> List.map Domain.join
    end
  in
  let elapsed = Unix.gettimeofday () -. start in
  if List.exists (fun (_, c) -> c <> expected) results then begin
    prerr_endline "ERROR: wrong prime count";
    false
  end
  else begin
    let passes = List.fold_left (fun acc (p, _) -> acc + p) 0 results in
    Printf.printf "%s;%d;%.6f;%d;%s\n%!" label passes elapsed threads tags;
    true
  end

(* PRIMES_TEST=1: prime counts for every power of ten from 10 to 10^8 and a few awkward sizes. *)
let self_test () =
  let cases =
    [ (1, 0); (2, 1); (3, 2); (10, 4); (100, 25); (1_000, 168); (10_000, 1_229);
      (100_000, 9_592); (1_000_000, 78_498); (10_000_000, 664_579);
      (100_000_000, 5_761_455); (127, 31); (16_383, 1_900) ]
  in
  List.fold_left
    (fun ok (size, exp) ->
      let c = sieve_count size in
      Printf.printf "size %d -> %d primes (expected %d) %d\n%!" size c exp
        (if c = exp then 1 else 0);
      ok && c = exp)
    true cases

(* PRIMES_TEST is on when it holds a nonzero unsigned 32-bit number, as in the Rust port. *)
let test_requested () =
  match Sys.getenv_opt "PRIMES_TEST" with
  | None -> false
  | Some v ->
      let v = String.trim v in
      let v =
        if String.length v > 1 && v.[0] = '+' then String.sub v 1 (String.length v - 1) else v
      in
      v <> ""
      && String.length v <= 10
      && String.for_all (fun ch -> ch >= '0' && ch <= '9') v
      && (let n = int_of_string v in n <> 0 && n <= 0xFFFF_FFFF)

let () =
  if test_requested () then exit (if self_test () then 0 else 1);
  (* One domain, then all hardware threads, then exactly four when there are more than four. *)
  let hw = max 1 (Domain.recommended_domain_count ()) in
  let runs = if hw > 4 then [ 1; hw; 4 ] else if hw > 1 then [ 1; hw ] else [ 1 ] in
  List.iter (fun threads -> if not (timed_run threads) then exit 1) runs
