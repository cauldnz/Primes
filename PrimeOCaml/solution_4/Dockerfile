FROM ocaml/opam:debian-12-ocaml-5.2-flambda AS build

# /home/opam belongs to the opam user, so the compiler can write its output there.
WORKDIR /home/opam
COPY --chown=opam:opam primes.ml build.sh ./
RUN opam exec -- sh build.sh

FROM debian:12-slim

WORKDIR /app
COPY --from=build /home/opam/primes primes

ENTRYPOINT [ "./primes" ]
