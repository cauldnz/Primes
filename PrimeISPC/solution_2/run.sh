#!/bin/sh
# DIAGNOSTIC ONLY: run every AVX2-only (Skylake-target) build in this image with its default
# command. Each entry prints its own drag-race lines (name;passes;time;threads;tags).
# PRIMES_TEST set: run our ISPC base's self-test only, so the bench harness's check passes.
cd "$(dirname "$0")" || exit 1
if [ -n "$PRIMES_TEST" ]; then exec ./ispc-base; fi

cpu() { lscpu 2>/dev/null | sed -n "s/^$1:[[:space:]]*//p" | head -1; }
echo "diag;lscpu;Model name;$(cpu 'Model name')"
echo "diag;lscpu;CPU(s);$(cpu 'CPU(s)')"
echo "diag;lscpu;Thread(s) per core;$(cpu 'Thread(s) per core')"
echo "diag;lscpu;Core(s) per socket;$(cpu 'Core(s) per socket')"
echo "diag;lscpu;Socket(s);$(cpu 'Socket(s)')"
for f in avx2 avx512f; do
    if grep -qw "$f" /proc/cpuinfo; then echo "diag;flags;$f;yes"; else echo "diag;flags;$f;no"; fi
done
echo "diag;build;all entries built for skylake / avx2 only"

./ispc-base
./ispc-wheel
./prime-sieve-rust --bits-extreme
./primes_array.exe -l 1000000 -t 1
./primes_array.exe -l 1000000
./zig-primes
# C5: what its image's default (./sieve runall --verbose 0) runs, with mimalloc preloaded as its
# Dockerfile does; the binaries are musl-linked (loader at /lib/ld-musl-x86_64.so.1).
for b in sieve_extend_epar; do LD_PRELOAD=/opt/c5/lib/libmimalloc.so "/opt/c5/bin/$b" --threads all --verbose 0; done
for b in sieve_extend sieve_base sieve_classic64 sieve_classic8; do
    LD_PRELOAD=/opt/c5/lib/libmimalloc.so "/opt/c5/bin/$b" --verbose 0
done
exit 0
