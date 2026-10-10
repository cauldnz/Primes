#!/bin/sh
# DIAGNOSTIC BUILD (hc/diag-swift-phases): never merge.
# Runs the instrumented striped binary once: phase profile lines, then the normal
# benchmark line. With PRIMES_TEST set (not 0) it runs only the correctness check.

set -eu
cd "$(dirname "$0")"

exec ./PrimeSwift_1bitStriped_u8/.build/release/PrimeSieveSwift
