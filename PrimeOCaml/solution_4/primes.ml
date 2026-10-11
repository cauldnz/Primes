(* Prime sieve drag race: an OCaml base-algorithm solution by cauldnz.

   The base algorithm: an outer loop finds the next prime, then clears every one of its odd
   multiples individually. Bit i of the sieve stands for the odd number 2i + 1; a set bit means
   composite.

   This is the design of the author's ISPC base entry (PrimeISPC/solution_2) and its Rust port
   (PrimeRust/solution_9), written in plain OCaml 5:

   - Dense (factor below 128): the odd multiples of p repeat with a period of p 64-bit words.
     For each factor the sieve builds the word pattern of four periods (4p words) in its own
     scratch buffer, setting each of their 256 multiples with its own single-bit OR, then ORs
     the pattern into the sieve one word at a time. Each loop step covers four words of two
     consecutive runs, so one load of a pattern word serves two sieve words.
   - Sparse (larger factors): eight multiples repeat every p bytes, each at a fixed bit. The
     byte offsets and masks are computed per factor; each composite is one byte OR.

   The sieve is a [Bytes] buffer of 64-bit little-endian words, read and written as 32-bit
   halves or as bytes. The 32-bit accesses go through the compiler's unboxed primitives, so the
   inner loops do not allocate. *)

external get32 : Bytes.t -> int -> int32 = "%caml_bytes_get32u"
external set32 : Bytes.t -> int -> int32 -> unit = "%caml_bytes_set32u"

let sieve_size = 1_000_000
let expected = 78_498
let run_time = 5.0
let label = "cauldnz-ocaml-base"
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
  set32 bits 0 0l;
  set32 bits 4 0l;
  { size; nbits; nwords; bits; pattern = Bytes.create (dense_limit * 32) }

let[@inline always] is_composite s i =
  (Char.code (Bytes.unsafe_get s.bits (i lsr 3)) lsr (i land 7)) land 1 <> 0

(* The word pattern of one run of four periods (4p 64-bit words, 8p 32-bit words) for odd
   factor p: 32-bit word t lsr 5 of the run gets bit t land 31 for each multiple p(2j + 1), at
   bit t = p/2 + jp, j = 0..255. One single-bit OR per composite. *)
let build_pattern s p =
  let pat = s.pattern in
  Bytes.fill pat 0 (p * 32) '\000';
  for j = 0 to 255 do
    let t = (p lsr 1) + (j * p) in
    let a = (t lsr 5) * 4 in
    set32 pat a (Int32.logor (get32 pat a) (Int32.shift_left 1l (t land 31)))
  done

(* Dense clearing for odd p < dense_limit. Periods of p words start at word multiples of p;
   clearing starts at the period holding p². The smaller multiples in that period are
   composite too, except p itself, which is restored at the end. The loop walks runs of four
   periods, two runs and eight 64-bit words at a time; the last, partial run takes as many
   words of the pattern as fit. With [init] (the first factor, 3) every word is stored without
   being loaded, which initialises the buffer.

   Every access is a 32-bit load or store, two per 64-bit word. Under the OCaml 5 memory model
   a 64-bit store to [Bytes] on Arm64 is preceded by a load barrier (dmb ishld), one per store;
   32-bit stores have none. *)
let clear_dense s p init =
  build_pattern s p;
  let b = s.bits and pat = s.pattern and n = s.nwords in
  let c0 = p * p / 2 / 64 / p * p in
  let runs = (n - c0) / (4 * p) in
  let rb = p * 32 in
  let base = ref (c0 * 8) in
  if init then
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
  else begin
    (* Two runs per step: each pattern word is loaded once and ORed into the same word of two
       consecutive runs, eight 64-bit sieve words a step. *)
    for _ = 1 to runs / 2 do
      let q = !base in
      let v = ref 0 in
      while !v < rb do
        let a = q + !v and v0 = !v in
        let a2 = a + rb in
        (* Four halves at a time, so the loaded pattern words stay in registers. *)
        let w0 = get32 pat v0 and w1 = get32 pat (v0 + 4)
        and w2 = get32 pat (v0 + 8) and w3 = get32 pat (v0 + 12) in
        set32 b a (Int32.logor (get32 b a) w0);
        set32 b (a + 4) (Int32.logor (get32 b (a + 4)) w1);
        set32 b (a + 8) (Int32.logor (get32 b (a + 8)) w2);
        set32 b (a + 12) (Int32.logor (get32 b (a + 12)) w3);
        set32 b a2 (Int32.logor (get32 b a2) w0);
        set32 b (a2 + 4) (Int32.logor (get32 b (a2 + 4)) w1);
        set32 b (a2 + 8) (Int32.logor (get32 b (a2 + 8)) w2);
        set32 b (a2 + 12) (Int32.logor (get32 b (a2 + 12)) w3);
        let w4 = get32 pat (v0 + 16) and w5 = get32 pat (v0 + 20)
        and w6 = get32 pat (v0 + 24) and w7 = get32 pat (v0 + 28) in
        set32 b (a + 16) (Int32.logor (get32 b (a + 16)) w4);
        set32 b (a + 20) (Int32.logor (get32 b (a + 20)) w5);
        set32 b (a + 24) (Int32.logor (get32 b (a + 24)) w6);
        set32 b (a + 28) (Int32.logor (get32 b (a + 28)) w7);
        set32 b (a2 + 16) (Int32.logor (get32 b (a2 + 16)) w4);
        set32 b (a2 + 20) (Int32.logor (get32 b (a2 + 20)) w5);
        set32 b (a2 + 24) (Int32.logor (get32 b (a2 + 24)) w6);
        set32 b (a2 + 28) (Int32.logor (get32 b (a2 + 28)) w7);
        v := v0 + 32
      done;
      base := q + (2 * rb)
    done;
    (* An odd run left over: one run, four 64-bit words a step. *)
    if runs land 1 = 1 then begin
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
    end
  end;
  (* The partial last run: fewer than 4p words, one 32-bit half at a time. *)
  let q = !base in
  let left = (n * 8) - q in
  let v = ref 0 in
  while !v < left do
    let a = q + !v in
    let x = if init then 0l else get32 b a in
    set32 b a (Int32.logor x (get32 pat !v));
    v := !v + 4
  done;
  (* p itself is prime. *)
  let f = p lsr 1 in
  let i = f lsr 3 in
  Bytes.unsafe_set b i
    (Char.unsafe_chr (Char.code (Bytes.unsafe_get b i) land lnot (1 lsl (f land 7))))

(* Sparse clearing over bytes for odd p >= dense_limit. Chunks of p bytes start at byte
   multiples of p; in each, the eight multiples p(2j + 1), j = 0..7, sit at fixed byte offsets
   o_j = (p/2 + jp) / 8 with fixed single-bit masks. *)
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
  let[@inline always] mark a m =
    Bytes.unsafe_set b a (Char.unsafe_chr (Char.code (Bytes.unsafe_get b a) lor m))
  in
  let s0 = p * p / 2 / 8 / p * p in
  let chunks = (nbytes - s0) / p in
  let q = ref s0 in
  for _ = 1 to chunks do
    let a = !q in
    mark (a + o0) m0;  (* one composite each *)
    mark (a + o1) m1;
    mark (a + o2) m2;
    mark (a + o3) m3;
    mark (a + o4) m4;
    mark (a + o5) m5;
    mark (a + o6) m6;
    mark (a + o7) m7;
    q := a + p
  done;
  (* Partial last chunk: the offsets increase, so stop at the first one past the end. *)
  let a = !q in
  let left = nbytes - a in
  if o0 < left then begin
    mark (a + o0) m0;
    if o1 < left then begin
      mark (a + o1) m1;
      if o2 < left then begin
        mark (a + o2) m2;
        if o3 < left then begin
          mark (a + o3) m3;
          if o4 < left then begin
            mark (a + o4) m4;
            if o5 < left then begin
              mark (a + o5) m5;
              if o6 < left then begin
                mark (a + o6) m6;
                if o7 < left then mark (a + o7) m7
              end
            end
          end
        end
      end
    end
  end

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
