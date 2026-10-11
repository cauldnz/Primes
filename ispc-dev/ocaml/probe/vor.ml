(* Probe (ii): OR 128-bit and 256-bit vectors loaded from Bytes and store
   the result back. dst.(i) <- dst.(i) lor src.(i), 16 or 32 bytes at a time.
   Build with -extension simd (AVX is on by default when the build CPU has it). *)

(* Unaligned, unchecked loads and stores on Bytes. The boxed vector types are
   fine here: flambda2 keeps them in xmm/ymm registers inside the loop. *)
external get128 : bytes -> int -> int64x2 = "%caml_bytes_getu128u"
external set128 : bytes -> int -> int64x2 -> unit = "%caml_bytes_setu128u"
external get256 : bytes -> int -> int64x4 = "%caml_bytes_getu256u"
external set256 : bytes -> int -> int64x4 -> unit = "%caml_bytes_setu256u"

external or128 : int64x2 -> int64x2 -> int64x2
  = "caml_vec128_unreachable" "caml_sse_vec128_or"
  [@@noalloc] [@@unboxed] [@@builtin]

external or256 : int64x4 -> int64x4 -> int64x4
  = "caml_vec256_unreachable" "caml_avx_vec256_or"
  [@@noalloc] [@@unboxed] [@@builtin]

let n = 1 lsl 16  (* 64KB buffers, L2-resident *)
let reps = 20_000

let or_loop128 dst src =
  let i = ref 0 in
  while !i < n do
    set128 dst !i (or128 (get128 dst !i) (get128 src !i));
    i := !i + 16
  done

let or_loop256 dst src =
  let i = ref 0 in
  while !i < n do
    set256 dst !i (or256 (get256 dst !i) (get256 src !i));
    i := !i + 32
  done

(* Scalar baseline: 64-bit words with unsafe primitives. *)
external get64u : bytes -> int -> int64 = "%caml_bytes_get64u"
external set64u : bytes -> int -> int64 -> unit = "%caml_bytes_set64u"

let or_loop64 dst src =
  let i = ref 0 in
  while !i < n do
    set64u dst !i (Int64.logor (get64u dst !i) (get64u src !i));
    i := !i + 8
  done

let check name f =
  let dst = Bytes.init n (fun i -> Char.chr (i land 0x55)) in
  let src = Bytes.init n (fun i -> Char.chr ((i * 7) land 0xaa)) in
  let want = Bytes.init n (fun i ->
    Char.chr (Char.code (Bytes.get dst i) lor Char.code (Bytes.get src i))) in
  f dst src;
  let ok = Bytes.equal dst want in
  let t0 = Sys.time () in
  for _ = 1 to reps do f dst src done;
  let dt = Sys.time () -. t0 in
  Printf.printf "%-6s %s  %.2f GB/s (dst read+write, src read)\n" name
    (if ok then "ok" else "WRONG")
    (float (n * reps) /. dt /. 1e9)

let () =
  check "or64" or_loop64;
  check "or128" or_loop128;
  check "or256" or_loop256
