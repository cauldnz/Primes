FROM ubuntu:24.04 AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends ispc gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/app
ARG ISPC_TARGETS
COPY primes_base.ispc build.sh ./
RUN sh build.sh

FROM rust:1.57 AS rust
WORKDIR /app
COPY rust/ ./
RUN cargo build --release

FROM ubuntu:24.04

WORKDIR /opt/app
COPY --from=build /opt/app/primes .
COPY --from=rust /app/target/release/prime-sieve-rust .
COPY run.sh .

ENTRYPOINT [ "./run.sh" ]
