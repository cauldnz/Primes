#!/bin/sh
# Needs Fai 0.1.0 on PATH and a C toolchain: `fai build` links with `cc` (or $CC).
# --release is accepted but has no effect in 0.1.0; it is kept for later versions.
# Two binaries: `primes` (the single-threaded run, the self-test and the worker mode) and
# `primes-parallel` (the multi-threaded runs, one `primes --worker` process per thread).
# The empty fai.toml makes this directory a workspace, so PrimesParallel.fai sees Primes.fai.
set -e
fai build --no-daemon --release --out primes Primes.fai
fai build --no-daemon --release --out primes-parallel PrimesParallel.fai
