/* OxCaml inlines [@@builtin] externals, but the object file still lists
   their native names, so the linker wants the symbols to exist. These are
   never called. Same trick as oxcaml/tests/simd/amd64/stub_builtins.c. */
#include <stdlib.h>
#define BUILTIN(name) void name(void) { abort(); }
BUILTIN(caml_sse_vec128_or)
BUILTIN(caml_avx_vec256_or)
