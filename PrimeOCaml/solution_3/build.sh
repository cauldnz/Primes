#!/bin/sh
# Needs the OxCaml compiler (opam switch 5.2.0+ox, flambda2).
# The dense copy loops come from amd64/ (256-bit AVX vectors) on x86-64 and from scalar/
# (64-bit words) everywhere else. OxCaml's SIMD types are x86-64 only.
# The OCaml 5 Domain.spawn alerts are switched off: OxCaml wants its own threading library, but
# this program spawns at most as many domains as recommended_domain_count.
set -e
case "$(uname -m)" in
  x86_64|amd64) d=amd64; extra=amd64/simd_stubs.c ;;
  *) d=scalar; extra= ;;
esac
ocamlopt -O3 -unsafe -alert -do_not_spawn_domains -alert -unsafe_multidomain \
  -I +unix -I $d unix.cmxa $extra $d/dense.ml primes.ml -o primes
