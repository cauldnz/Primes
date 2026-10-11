#!/bin/sh
# Needs an OCaml 5.2 compiler built with flambda; -O3 has no effect without it.
set -e
ocamlopt -O3 -unsafe -inline 200 -I +unix unix.cmxa primes.ml -o primes
