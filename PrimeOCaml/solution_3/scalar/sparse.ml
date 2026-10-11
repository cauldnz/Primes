(* Sparse clearing, portable version: one byte OR per composite. build.sh uses this on every
   architecture other than x86-64. On Arm Neoverse N2 the 64-bit word OR form in
   amd64/sparse.ml was 28% slower.

   Sparse clearing over bytes for odd p >= 128 on the sieve [b] of [nbytes] bytes. Chunks of p
   bytes start at byte multiples of p; in each, the eight multiples p(2j + 1), j = 0..7, sit at
   fixed byte offsets o_j = (p/2 + jp) / 8 with fixed single-bit masks. *)
let clear b nbytes p =
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
