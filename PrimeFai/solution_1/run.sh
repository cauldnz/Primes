#!/bin/sh
# The single-threaded run (or the PRIMES_TEST self-test), then the multi-threaded runs.
dir=$(dirname "$0")
"$dir/primes" || exit $?
exec "$dir/primes-parallel"
