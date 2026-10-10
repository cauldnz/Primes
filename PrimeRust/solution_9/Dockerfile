# Debian rather than Alpine: musl's malloc is slow for a sieve allocated on every pass.
FROM rust:1.85-slim-bookworm AS build

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY .cargo .cargo
COPY src src
RUN cargo build --release

FROM debian:bookworm-slim

WORKDIR /app
COPY --from=build /app/target/release/primes-base primes-base

ENTRYPOINT [ "./primes-base" ]
