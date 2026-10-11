# The OxCaml toolchain image: Ubuntu 24.04 with the 5.2.0+ox switch on PATH, running as root.
# Dockerfile.standalone builds the same toolchain from scratch.
FROM oxcaml:5.2.0-ox AS build

WORKDIR /build
COPY primes.ml build.sh ./
RUN sh build.sh

FROM ubuntu:24.04

WORKDIR /app
COPY --from=build /build/primes primes

ENTRYPOINT [ "./primes" ]
