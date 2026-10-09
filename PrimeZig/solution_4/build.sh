#!/bin/sh
# Build the Zig prime sieve for the CPU it is built on: the drag race builds each image on the
# machine that runs it, as the C++ (-march=native) and Rust (target-cpu=native) entries assume.
# Set ZIG_CPU to override, for example ZIG_CPU=baseline for a portable binary.
set -e
ZIG="${ZIG:-zig}"
"$ZIG" build-exe primes.zig -O ReleaseFast -fstrip -mcpu="${ZIG_CPU:-native}" -femit-bin=primes
