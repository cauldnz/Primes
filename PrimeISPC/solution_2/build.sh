#!/bin/sh
# Build the ISPC base-algorithm prime sieve.
# The base algorithm clears one composite per operation, so this program is essentially scalar
# code and gains nothing from wide vectors: the AVX-512 target measured ~18% slower than AVX2,
# and ISPC's dispatcher would pick it on AVX-512 machines, so it is left out. On ARM64 it
# targets NEON. Set ISPC_TARGETS to override.
set -e
ISPC="${ISPC:-ispc}"
case "$(uname -m)" in
    x86_64|amd64)  TARGETS="${ISPC_TARGETS:-sse4-i32x4,avx2-i32x8}" ;;
    aarch64|arm64) TARGETS="${ISPC_TARGETS:-neon-i32x4}" ;;
    *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
"$ISPC" -O3 --pic --woff --target="$TARGETS" primes_base.ispc -o primes.o
${CC:-gcc} -o primes primes*.o -lpthread
