/* The SIMD operations declared in dense.ml are compiler builtins: ocamlopt emits the
   instruction inline and never calls a function. They are still listed by C name among the
   program's external symbols, so the linker needs definitions. These are never reached;
   they abort if they ever are. No sieving happens here. */
#include <stdlib.h>

void caml_avx_vec256_or(void) { abort(); }
void caml_avx_vec256_xor(void) { abort(); }
