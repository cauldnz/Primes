/* The SIMD operation declared in dense.ml is a compiler builtin: ocamlopt emits the
   instruction inline and never calls a function. It still lists the C name among the
   program's external symbols, so the linker needs a definition. This one is never reached;
   it aborts if it ever is. No sieving happens here. */
#include <stdlib.h>

void caml_avx_vec256_or(void) { abort(); }
