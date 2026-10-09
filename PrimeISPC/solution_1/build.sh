#!/bin/sh
# Build the ISPC prime sieve.
# On x86-64 one binary carries SSE4, AVX2 and AVX-512 code paths; ISPC's dispatcher picks the
# best one the CPU supports at startup. On ARM64 it targets NEON.
set -e
ISPC="${ISPC:-ispc}"
case "$(uname -m)" in
    x86_64|amd64)  TARGETS="sse4-i32x4,avx2-i32x8,avx512skx-x16" ;;
    aarch64|arm64) TARGETS="neon-i32x4" ;;
    *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
"$ISPC" -O3 --pic --woff --target="$TARGETS" primes.ispc -o primes.o
${CC:-gcc} -o primes primes*.o -lpthread
