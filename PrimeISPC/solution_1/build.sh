#!/bin/sh
# Build the ISPC prime sieve.
# On x86-64 one binary carries several code paths and ISPC's dispatcher picks the best one the
# CPU supports at startup. On ARM64 it targets NEON. Set ISPC_TARGETS to override.
#
# The hot loops stream sieve words, so wider gangs (more words per iteration than the vector
# registers hold) win: avx2-i32x16 beat avx2-i32x8 by 12-16% on Zen 3-5 (25% on an Intel
# Xeon), and sse4-i32x8 beat sse4-i32x4 by about 15%. On arm64, neon-i32x8 beat neon-i32x4 by 4% (Neoverse N1)
# and 15% (Neoverse N2).
set -e
ISPC="${ISPC:-ispc}"
case "$(uname -m)" in
    x86_64|amd64)  TARGETS="${ISPC_TARGETS:-sse4-i32x8,avx2-i32x16,avx512skx-x16}" ;;
    aarch64|arm64) TARGETS="${ISPC_TARGETS:-neon-i32x8}" ;;
    *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
# Constant tables (start bits and patterns of the primes below 10,000) are generated first; see
# gen_tables.c. They depend only on those primes, not on the sieve size.
${HOSTCC:-gcc} -O2 -o gen_tables gen_tables.c
./gen_tables ${PRIMES_TABLE_LIMIT:-10000} > primes_tables.h
"$ISPC" -O3 --addressing=64 --pic --woff --target="$TARGETS" primes.ispc -o primes.o
${CC:-gcc} -o primes primes*.o -lpthread
