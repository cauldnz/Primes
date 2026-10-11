(* Probe (iii): spawn four domains, each running the same sieve on its own
   buffer, and join them. Two ways: plain Domain.spawn (raises alerts in
   OxCaml) and Domain.Safe.spawn (needs a portable closure). *)

let limit = 1_000_000
let nbits = limit / 2

external get64u : bytes -> int -> int64 @@ portable = "%caml_bytes_get64u"
external set64u : bytes -> int -> int64 -> unit @@ portable = "%caml_bytes_set64u"

let sieve @ portable = fun () ->
  let buf = Bytes.make (((nbits + 63) / 64) * 8) '\xff' in
  let is_set k =
    Char.code (Bytes.unsafe_get buf (k lsr 3)) land (1 lsl (k land 7)) <> 0 in
  let f = ref 1 in
  while (2 * !f + 1) * (2 * !f + 1) <= limit do
    if is_set !f then begin
      let p = 2 * !f + 1 in
      let i = ref ((p * p) / 2) in
      while !i < nbits do
        let k = !i in
        let off = (k lsr 6) lsl 3 in
        set64u buf off
          (Int64.logand (get64u buf off)
             (Int64.lognot (Int64.shift_left 1L (k land 63))));
        i := k + p
      done
    end;
    incr f
  done;
  let c = ref 1 in
  for k = 1 to nbits - 1 do if is_set k then incr c done;
  !c

let passes @ portable = fun () ->
  let r = ref 0 in
  for _ = 1 to 100 do r := sieve () done;
  !r

let () =
  Printf.printf "recommended_domain_count=%d\n" (Domain.recommended_domain_count ());
  (* Plain spawn: works, but OxCaml marks it with two alerts. *)
  let ds = List.init 4 (fun _ ->
    (Domain.spawn [@alert "-do_not_spawn_domains"] [@alert "-unsafe_multidomain"])
      passes) in
  List.iteri (fun i d -> Printf.printf "spawn      domain %d: %d primes\n" i (Domain.join d)) ds;
  (* Safe spawn: the closure must be portable; [passes] is a top-level
     function that touches no mutable globals, so it qualifies. *)
  let ds = List.init 4 (fun _ ->
    (Domain.Safe.spawn [@alert "-do_not_spawn_domains"]) passes) in
  List.iteri (fun i d -> Printf.printf "Safe.spawn domain %d: %d primes\n" i (Domain.join d)) ds
