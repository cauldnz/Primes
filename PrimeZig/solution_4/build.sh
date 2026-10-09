#!/bin/sh
# Build the Zig prime sieve. The target CPU is the architecture's baseline (SSE2 on x86-64,
# Armv8-A on arm64), so one image runs on every benchmark machine. Set ZIG_CPU to override,
# for example ZIG_CPU=native.
set -e
ZIG="${ZIG:-zig}"
"$ZIG" build-exe primes.zig -O ReleaseFast -fstrip -mcpu="${ZIG_CPU:-baseline}" -femit-bin=primes
