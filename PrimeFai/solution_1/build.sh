#!/bin/sh
# Needs Fai 0.1.0 on PATH and a C toolchain: `fai build` links with `cc` (or $CC).
# --release is accepted but has no effect in 0.1.0; it is kept for later versions.
set -e
fai build --no-daemon --release --out primes Primes.fai
