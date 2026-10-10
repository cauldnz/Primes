# DIAGNOSTIC ONLY (branch hc/diag-intel-avx2), never merged.
# Builds our ISPC base and wheel, the Zig base/wheel and three rivals for an AVX2-only
# Skylake-class target (stand-in for the official i7-9750H, which has no AVX-512) and runs
# them all from one image. See run.sh.

# ---- ISPC base and wheel: AVX2 only (the targets runtime dispatch picks on the i7) ----
FROM ubuntu:24.04 AS ispc
RUN apt-get update \
    && apt-get install -y --no-install-recommends ispc gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/base
COPY ispc-base/ ./
RUN ISPC_TARGETS=avx2-i32x8 sh build.sh
WORKDIR /opt/wheel
COPY ispc-wheel/ ./
RUN ISPC_TARGETS=avx2-i32x16 sh build.sh

# ---- mike-barber Rust (PrimeRust/solution_1), target-cpu=skylake ----
FROM rust:1.57 AS rust
RUN cargo search num_cpus -q --limit 1
WORKDIR /app
COPY rust/ ./
# RUSTFLAGS replaces the solution's .cargo/config target-cpu=native (not copied here).
ENV RUSTFLAGS="-C target-cpu=skylake"
RUN cargo test && cargo build --release

# ---- davepl C++ (PrimeCPP/solution_5), -march=skylake ----
FROM ubuntu:22.04 AS cpp
RUN apt-get update -qq \
    && apt-get install -y bash clang lld \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/app
COPY cpp/ ./
RUN clang++ -march=skylake -mtune=skylake -pthread -O3 -ffast-math -fno-math-errno -fno-trapping-math \
        -flto -std=c++17 -fuse-ld=lld PrimeCPP_array.cpp -o primes_array.exe

# ---- rogiervandam C (PrimeC/solution_5), its own script with -march/-mtune=skylake ----
FROM alpine:3.21.3 AS c5
RUN apk add --no-cache build-base mimalloc2-dev clang openmp-dev bash
WORKDIR /home/sieve
COPY c5/ ./
SHELL ["/bin/ash", "-o", "pipefail", "-c"]
RUN sed -i 's/\r$//; s/-march=native/-march=skylake/g; s/-mtune=native/-mtune=skylake/g' ./sieve \
    && ! grep -qE 'm(arch|tune)=native' ./sieve \
    && chmod +x ./sieve && mkdir -p bin dev/build && ./sieve compileall \
    && mkdir /c5lib \
    && { for b in bin/*; do ldd "$b" || true; done; } | awk '/=>/ {print $3}' | sort -u | xargs -r -I{} cp -L {} /c5lib/ \
    && cp -L /usr/lib/libmimalloc.so /c5lib/libmimalloc.so

# ---- cauldnz Zig base and wheel (PrimeZig/solution_4 at hc/zig-submission), -mcpu=skylake ----
FROM alpine:3.21 AS zig
RUN apk add --no-cache zig=0.13.0-r1
WORKDIR /opt/app
COPY zig/ ./
RUN ZIG_CPU=skylake sh build.sh

# ---- runtime ----
FROM ubuntu:24.04
WORKDIR /opt/diag
COPY --from=ispc /opt/base/primes ispc-base
COPY --from=ispc /opt/wheel/primes ispc-wheel
COPY --from=rust /app/target/release/prime-sieve-rust prime-sieve-rust
COPY --from=cpp /opt/app/primes_array.exe primes_array.exe
COPY --from=zig /opt/app/primes zig-primes
# The C5 binaries are musl-linked: carry musl's loader and their libraries (libgomp, mimalloc).
COPY --from=c5 /lib/ld-musl-x86_64.so.1 /lib/ld-musl-x86_64.so.1
COPY --from=c5 /c5lib/ /opt/c5/lib/
COPY --from=c5 /home/sieve/bin/ /opt/c5/bin/
RUN echo /opt/c5/lib > /etc/ld-musl-x86_64.path
COPY run.sh ./
ENTRYPOINT [ "sh", "./run.sh" ]
