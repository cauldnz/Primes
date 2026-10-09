#!/bin/sh
# Build the ISPC prime sieve.
# On x86-64 one binary carries several code paths and ISPC's dispatcher picks the best one the
# CPU supports at startup. On ARM64 it targets NEON. Set ISPC_TARGETS to override.
#
# The hot loops stream sieve words, so wider gangs (more words per iteration than the vector
# registers hold) win: avx2-i32x16 measured ~25% faster than avx2-i32x8, and sse4-i32x8
# ~15% faster than sse4-i32x4.
set -e
ISPC="${ISPC:-ispc}"
case "$(uname -m)" in
    x86_64|amd64)  TARGETS="${ISPC_TARGETS:-sse4-i32x8,avx2-i32x16,avx512skx-x16}" ;;
    aarch64|arm64) TARGETS="${ISPC_TARGETS:-neon-i32x4}" ;;
    *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
"$ISPC" -O3 --pic --woff --target="$TARGETS" primes.ispc -o primes.o
${CC:-gcc} -o primes primes*.o -lpthread
