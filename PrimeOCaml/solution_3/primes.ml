(* DIAGNOSTIC BUILD (experiment ox-012), not for submission. The OxCaml champion's primes.ml
   (PrimeOCaml/solution_3 at 4f1ba99) with the same Dense and Sparse modules, plus a timed copy
   of the sieve loop with tick timers around each phase (the design of ox-005): setup (create),
   dense pattern build, dense copy (runs, partial run, restore p), sparse, next-prime scan.

   Ticks come from diag_stub.c: rdtsc on x86-64 (TSC cycles), cntvct_el0 on aarch64 (generic
   timer at cntfrq_el0, not CPU cycles), clock_gettime elsewhere. TSC ticks are converted to
   ns by calibration against CLOCK_MONOTONIC over the measured passes. The cost of a timer
   pair is measured and taken out of each phase.

   PRIMES_TEST=1 runs the normal self-test. Otherwise: DIAG_PASSES (default 3000) one-thread
   passes after 200 warm-up passes, printed as
     cauldnz-oxcaml-diag;<phase>;<ns per pass>;<share percent>;<cycles per pass or 0>
   with a final total line, then one normal 5-second one-thread run of the untimed loop. *)

external ticks : unit -> (int [@untagged]) = "diag_ticks_byte" "diag_ticks" [@@noalloc]
external mono_ns : unit -> (int [@untagged]) = "diag_mono_ns_byte" "diag_mono_ns" [@@noalloc]
external tick_hz : unit -> int = "diag_tick_hz"
external ticks_are_cycles : unit -> bool = "diag_ticks_are_cycles"

let t_create = ref 0 and t_build = ref 0 and t_copy = ref 0 and t_sparse = ref 0
and t_scan = ref 0
let n_dense_f = ref 0 and n_sparse_f = ref 0 and n_scan = ref 0

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
     byte offsets and masks are computed per factor; each composite is one OR of a single-bit
     mask. This loop lives in module Sparse, also picked by build.sh: on x86-64
     (amd64/sparse.ml) it ORs the mask into a 64-bit word with untagged offsets; elsewhere
     (scalar/sparse.ml) it does one byte OR.

   The sieve is a [Bytes] buffer read and written as 64-bit little-endian words or as bytes.
   The 64-bit accesses go through the compiler's unboxed primitives, so the inner loops do not
   allocate. *)

external get64 : Bytes.t -> int -> int64 = "%caml_bytes_get64u"
external set64 : Bytes.t -> int -> int64 -> unit = "%caml_bytes_set64u"

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
      if p < dense_limit then clear_dense s p (p = 3)
      else Sparse.clear s.bits (s.nwords * 8) p;
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

(* ---- Timed copies of clear_dense and run (diagnostic): the same code with timers. ---- *)

let clear_dense_t s p init =
  let t0 = ticks () in
  build_pattern s p;
  let t1 = ticks () in
  t_build := !t_build + (t1 - t0);
  let b = s.bits and pat = s.pattern and n = s.nwords in
  let c0 = p * p / 2 / 64 / p * p in
  let runs = (n - c0) / (4 * p) in
  let rb = p * 32 in
  let q =
    if init then Dense.store_runs b pat (c0 * 8) runs rb
    else Dense.or_runs b pat (c0 * 8) runs rb
  in
  let left = (n * 8) - q in
  let v = ref 0 in
  while !v < left do
    let a = q + !v in
    let x = if init then 0L else get64 b a in
    set64 b a (Int64.logor x (get64 pat !v));
    v := !v + 8
  done;
  let f = p lsr 1 in
  let i = f lsr 3 in
  Bytes.unsafe_set b i
    (Char.unsafe_chr (Char.code (Bytes.unsafe_get b i) land lnot (1 lsl (f land 7))));
  t_copy := !t_copy + (ticks () - t1);
  incr n_dense_f

let run_t s =
  let q = ref (int_of_float (sqrt (float_of_int s.size))) in
  while (!q + 1) * (!q + 1) <= s.size do incr q done;
  while !q * !q > s.size do decr q done;
  let q = !q in
  let factor = ref 3 in
  let continue = ref true in
  while !continue && !factor <= q do
    let t0 = ticks () in
    let i = ref (!factor lsr 1) in
    while !i < s.nbits && is_composite s !i do incr i done;
    let p = (2 * !i) + 1 in
    t_scan := !t_scan + (ticks () - t0);
    incr n_scan;
    if p > q then continue := false
    else begin
      if p < dense_limit then clear_dense_t s p (p = 3)
      else begin
        let t0 = ticks () in
        Sparse.clear s.bits (s.nwords * 8) p;
        t_sparse := !t_sparse + (ticks () - t0);
        incr n_sparse_f
      end;
      factor := p + 2
    end
  done

let diag passes =
  for _ = 1 to 200 do let s = create sieve_size in run_t s done;
  let s = create sieve_size in
  run_t s;
  if count_primes s <> expected then begin
    prerr_endline "ERROR: wrong prime count (timed loop)";
    exit 1
  end;
  t_create := 0; t_build := 0; t_copy := 0; t_sparse := 0; t_scan := 0;
  n_dense_f := 0; n_sparse_f := 0; n_scan := 0;
  (* Cost of one timer pair, in ticks. *)
  let k = 100_000 in
  let o = ref 0 in
  for _ = 1 to k do let a = ticks () in o := !o + (ticks () - a) done;
  let ovh = float !o /. float k in
  let mw0 = Gc.minor_words () and jw0 = (Gc.quick_stat ()).major_words in
  let w0 = mono_ns () and c0 = ticks () in
  for _ = 1 to passes do
    let t0 = ticks () in
    let s = create sieve_size in
    t_create := !t_create + (ticks () - t0);
    run_t s
  done;
  let c1 = ticks () and w1 = mono_ns () in
  let mw1 = Gc.minor_words () and jw1 = (Gc.quick_stat ()).major_words in
  let fp = float passes in
  let ns_per_tick =
    let hz = tick_hz () in
    if hz > 0 then 1e9 /. float hz else float (w1 - w0) /. float (c1 - c0)
  in
  let cyc = ticks_are_cycles () in
  let total = float (c1 - c0) /. fp in
  let line name t =
    Printf.printf "cauldnz-oxcaml-diag;%s;%.1f;%.2f;%.0f\n" name (t *. ns_per_tick)
      (100. *. t /. total) (if cyc then t else 0.)
  in
  let per name tr calls = line name (Float.max 0. ((float !tr /. fp) -. (calls *. ovh))) in
  per "setup" t_create 1.;
  per "dense_pattern" t_build (float !n_dense_f /. fp);
  per "dense_copy" t_copy (float !n_dense_f /. fp);
  per "sparse" t_sparse (float !n_sparse_f /. fp);
  per "scan" t_scan (float !n_scan /. fp);
  line "total" total;
  (* ox-018: words allocated per timed pass, minor heap and major heap (direct major
     allocations included). The sieve and pattern buffers go straight to the major heap. *)
  Printf.printf "cauldnz-oxcaml-diag;minor_words_per_pass;%.1f;0;0\n" ((mw1 -. mw0) /. fp);
  Printf.printf "cauldnz-oxcaml-diag;major_words_per_pass;%.1f;0;0\n" ((jw1 -. jw0) /. fp);
  flush stdout

(* ox-018: print the assembly of the dense copy functions (or_runs, store_runs) from the
   dense.s that the Dockerfile keeps from the build, one line each as
   cauldnz-oxcaml-diag;asm;<line>;0;0 with ';' replaced by ','. Debug directives are dropped.
   At most [per_fn] lines per function. *)
let print_asm () =
  let path = match Sys.getenv_opt "DIAG_ASM" with Some p -> p | None -> "dense.s" in
  match open_in path with
  | exception Sys_error _ ->
      print_endline "cauldnz-oxcaml-diag;asm;(no dense.s);0;0"
  | ic ->
      let per_fn = 80 in
      let starts_with pre l =
        String.length l >= String.length pre && String.sub l 0 (String.length pre) = pre
      in
      let contains sub l =
        let n = String.length sub and m = String.length l in
        let rec go i = i + n <= m && (String.sub l i n = sub || go (i + 1)) in
        go 0
      in
      let is_fn_label l =
        (not (starts_with "." l)) && String.length l > 6
        && String.ends_with ~suffix:"_code:" l
        && (contains "or_runs" l || contains "store_runs" l)
      in
      let skip l =
        let t = String.trim l in
        t = "" || starts_with ".loc" t || starts_with ".cfi" t || starts_with ".file" t
        || starts_with ".type" t
      in
      let emit l =
        let l = String.map (fun c -> if c = ';' then ',' else if c = '\t' then ' ' else c) l in
        Printf.printf "cauldnz-oxcaml-diag;asm;%s;0;0\n" l
      in
      let inside = ref false and count = ref 0 in
      (try
         while true do
           let l = input_line ic in
           if !inside then begin
             let t = String.trim l in
             if starts_with ".size" t then inside := false
             else if not (skip l) then begin
               if !count < per_fn then emit l
               else if !count = per_fn then emit "  (truncated)";
               incr count
             end
           end
           else if is_fn_label l then begin
             inside := true;
             count := 0;
             emit l
           end
         done
       with End_of_file -> ());
      close_in ic;
      flush stdout

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
  let passes =
    match Sys.getenv_opt "DIAG_PASSES" with Some v -> int_of_string v | None -> 3000
  in
  diag passes;
  print_asm ();
  (* One normal one-domain run of the untimed loop. *)
  if not (timed_run 1) then exit 1
