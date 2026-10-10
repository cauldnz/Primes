#!/bin/sh
# Diagnostic only (never merged): why does Rust fall off when threads equal vCPUs?
# For K CPUs (N/2, N-2, N-1, N): ours limited to K CPUs by taskset (it sizes itself from the
# affinity mask), Rust with -t K pinned to the same K CPUs, and Rust with -t K unpinned.
if [ -n "$PRIMES_TEST" ]; then exec ./primes; fi
N=$(nproc)
lscpu | grep -E "Model name|Thread\(s\) per core|Core\(s\) per socket|Socket\(s\)|NUMA node\(s\)" | sed 's/  */ /g; s/^/diag;lscpu;/'
for K in $((N / 2)) $((N - 2)) $((N - 1)) "$N"; do
  L=$((K - 1))
  taskset -c "0-$L" ./primes | grep ";$K;" | sed "s/^cauldnz-ispc-base/ours-cpus$K/"
  taskset -c "0-$L" ./prime-sieve-rust --bits-extreme -t "$K" 2>/dev/null | grep "^mike" | sed "s/^mike-barber_bit-extreme-hybrid/rust-cpus$K/"
  ./prime-sieve-rust --bits-extreme -t "$K" 2>/dev/null | grep "^mike" | sed "s/^mike-barber_bit-extreme-hybrid/rust-free$K/"
done
