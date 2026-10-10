# DIAGNOSTIC BUILD (hc/diag-asm-sparse): never merge.
#
# Builds three faithful base sieves exactly as their own upstream Dockerfiles do, then the
# runtime image prints the disassembly of their sieve code (every line prefixed
# "asm;<entry>;"). It does not run any sieve.

# --- ISPC: the champion's base (PrimeISPC/solution_2 on hc/champion) -------------------
FROM ubuntu:24.04 AS ispc

RUN apt-get update \
    && apt-get install -y --no-install-recommends ispc gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/app
ARG ISPC_TARGETS
COPY ispc/primes_base.ispc ispc/build.sh ./
RUN sh build.sh

# --- Rust: PrimeRust/solution_1 (mike-barber), as its Dockerfile builds it --------------
FROM rust:1.57 AS rust
RUN cargo search num_cpus -q --limit 1

WORKDIR /app
COPY rust/ ./
RUN cargo build --release

# --- Swift: PrimeSwift/solution_1/PrimeSwift_1bitStriped_u8, as upstream builds it ------
FROM swift:6.3.3 AS swift

WORKDIR /opt/app
COPY swift/ ./PrimeSwift_1bitStriped_u8/

RUN if [ "$(uname -m)" = x86_64 ]; then set -- -Xswiftc -target-cpu -Xswiftc haswell; fi && \
    swift build -v --configuration release -Xswiftc -O -Xswiftc -whole-module-optimization "$@" --package-path PrimeSwift_1bitStriped_u8

# --- Runtime: objdump over the three binaries -------------------------------------------
FROM ubuntu:24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends binutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/app
COPY --from=ispc /opt/app/primes ./ispc-primes
COPY --from=rust /app/target/release/prime-sieve-rust ./prime-sieve-rust
COPY --from=swift /opt/app/PrimeSwift_1bitStriped_u8/.build/release/PrimeSieveSwift ./PrimeSieveSwift
COPY dump.sh ./dump.sh
RUN chmod +x ./dump.sh

ENTRYPOINT [ "./dump.sh" ]
