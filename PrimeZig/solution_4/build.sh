#!/bin/sh
# Build the Zig prime sieve for the CPU it is built on: the drag race builds each image on the
# machine that runs it, as the C++ (-march=native) and Rust (target-cpu=native) entries assume.
# Set ZIG_CPU to override, for example ZIG_CPU=baseline for a portable binary.
set -e
ZIG="${ZIG:-zig}"
# Zig 0.13 has no Zen 5 model: on Zen 5 "native" detects AVX-512 but not evex512, so LLVM emits
# no 512-bit instructions at all. Ask for them there.
CPU="${ZIG_CPU:-native}"
if [ -z "$ZIG_CPU" ] && grep -q AuthenticAMD /proc/cpuinfo 2>/dev/null &&
   grep -m1 '^cpu family' /proc/cpuinfo | grep -qw 26 && grep -qw avx512f /proc/cpuinfo; then
    CPU=native+evex512
fi
"$ZIG" build-exe primes.zig -O ReleaseFast -fstrip -mcpu="$CPU" -femit-bin=primes
