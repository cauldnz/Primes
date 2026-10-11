# Cold read of the final READMEs (run 10)

A fresh agent with no context read `PrimeOCaml/solution_3/README.md` on `hc/oxcaml-final`
(ec2d8e5) and `PrimeOCaml/solution_4/README.md` on `hc/ocaml-final` (e966e49) against
`WRITING.md`. Not yet applied; for the workshop before any PR.

Substance:
- solution_3 says two runs per step made no difference on Cobalt (−0.4%); solution_4 says it
  gained 23% there. Both are measured (ox-010, ocaml-004); the cause of the difference wasn't
  investigated. Say so in solution_3.
- solution_3's "+163% on Cobalt" for the compiler switch alone has no explanation (not
  investigated). Add "(cause not investigated)" or find it.
- solution_3 gives "16% to 33%" for the sparse word OR; the history table gives +17.4% / +26.6%
  for a row that also includes untagged offsets. Point to the table instead.
- "−3.0% ± 3.9": say the ± is the 95% interval and that "16 threads" is Zen 5.
- "an Intel Xeon": the local container's model isn't recorded; say "the shared development
  container's Intel Xeon (2.8 GHz)" or drop the number.

Wording (WRITING.md): "clears that factor's odd multiples" clashes with "a set bit means
composite" (use "marks ... as composite"); "every composite gets its own single-bit OR" needs
"when the pattern is built"; "OCaml has no const generics" is Rust jargon; several passives
("is computed", "is built", "is restored"); "5 seconds" should be "five seconds"; "made the
calls" is an idiom; "paired-run rule" and "gates" need a plain description; "That took 458
seconds" has no clear subject; solution_4 calls two items "three changes" and repeats its
opening sentence near the end.

The numbers in both Results sections match `results/hc/r10-final/README.md`.
