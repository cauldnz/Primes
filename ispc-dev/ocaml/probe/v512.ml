(* Probe: does a 512-bit load/store from Bytes compile? Needs -favx512f.
   OxCaml has the int64x8 type and the load/store primitives, but no AVX-512
   arithmetic intrinsics in this release. *)
external get512 : bytes -> int -> int64x8 = "%caml_bytes_getu512u"
external set512 : bytes -> int -> int64x8 -> unit = "%caml_bytes_setu512u"

let copy dst src = set512 dst 0 (get512 src 0)

let () =
  let a = Bytes.make 64 'a' and b = Bytes.make 64 'b' in
  copy a b;
  print_endline (if Bytes.equal a b then "v512 ok" else "v512 WRONG")
