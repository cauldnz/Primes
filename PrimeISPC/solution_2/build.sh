#!/bin/sh
# Build the ISPC base-algorithm prime sieve.
# Only the dense resets for small factors use SIMD lanes; everything else is scalar. The
# AVX-512 target uses 8 lanes (x8). On x86-64 a second object, the same source built with
# -DFOLD16 for avx512skx-x16, holds a 16-lane copy of the dense routine, which the AVX-512
# path uses when each sieve thread has a core to itself. On ARM64 it targets NEON. Set
# ISPC_TARGETS to override.
set -e
ISPC="${ISPC:-ispc}"
case "$(uname -m)" in
    x86_64|amd64)  TARGETS="${ISPC_TARGETS:-sse4-i32x4,avx2-i32x8,avx512skx-x8}"
                   "$ISPC" -O3 --pic --woff -DFOLD16 --target=avx512skx-x16 primes_base.ispc \
                       -o primes_x16.o ;;
    aarch64|arm64) TARGETS="${ISPC_TARGETS:-neon-i32x4}" ;;
    *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
"$ISPC" -O3 --pic --woff --target="$TARGETS" primes_base.ispc -o primes.o
${CC:-gcc} -o primes primes*.o -lpthread
