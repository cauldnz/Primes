#!/bin/sh
# Needs the OxCaml compiler (opam switch 5.2.0+ox, flambda2).
# The dense copy loops and the sparse loop come from amd64/ on x86-64 (256-bit AVX vectors;
# 64-bit word ORs with untagged offsets) and from scalar/ everywhere else (64-bit words; byte
# ORs). OxCaml's SIMD types are x86-64 only, and the word-OR sparse loop was slower on Arm.
# The OCaml 5 Domain.spawn alerts are switched off: OxCaml wants its own threading library, but
# this program spawns at most as many domains as recommended_domain_count.
# ox-020 diag: scalar/storevar.ml (store-primitive variants, timed by the diag) is linked on all targets.
set -e
case "$(uname -m)" in
  x86_64|amd64) d=amd64; extra=amd64/simd_stubs.c ;;
  *) d=scalar; extra= ;;
esac
ocamlopt -O3 -unsafe -alert -do_not_spawn_domains -alert -unsafe_multidomain \
  -I +unix -I $d -I scalar unix.cmxa $extra diag_stub.c $d/dense.ml $d/sparse.ml \
  scalar/storevar.ml primes.ml -o primes
