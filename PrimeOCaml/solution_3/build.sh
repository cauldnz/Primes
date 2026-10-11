#!/bin/sh
# Needs the OxCaml compiler (opam switch 5.2.0+ox, flambda2).
# The OCaml 5 Domain.spawn alerts are switched off: OxCaml wants its own threading library, but
# this program spawns at most as many domains as recommended_domain_count.
set -e
ocamlopt -O3 -unsafe -alert -do_not_spawn_domains -alert -unsafe_multidomain \
  -I +unix unix.cmxa primes.ml -o primes
