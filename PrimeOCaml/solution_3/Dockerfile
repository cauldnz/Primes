# The OxCaml toolchain image: Ubuntu 24.04 with the 5.2.0+ox switch on PATH, running as root.
# Dockerfile.standalone builds the same toolchain from scratch.
FROM oxcaml:5.2.0-ox AS build

WORKDIR /build
COPY primes.ml build.sh diag_stub.c ./
COPY amd64 amd64
COPY scalar scalar
RUN sh build.sh
# ox-018: the assembly of the dense copy module that build.sh picked, with the same flags.
RUN case "$(uname -m)" in x86_64|amd64) d=amd64 ;; *) d=scalar ;; esac \
 && mkdir asm && cp $d/dense.ml asm/ && cd asm && ocamlopt -O3 -unsafe -S -c dense.ml

FROM ubuntu:24.04

WORKDIR /app
COPY --from=build /build/primes primes
COPY --from=build /build/asm/dense.s dense.s

ENTRYPOINT [ "./primes" ]
