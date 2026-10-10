# DIAGNOSTIC BUILD (hc/diag-asm-wheel): never merge.
#
# Builds two wheel sieves on the benchmark node exactly as their own Dockerfiles do, then the
# runtime image prints the disassembly of their hot functions (every line prefixed
# "asm;<entry>;"). It runs no benchmark. PRIMES_TEST=1 runs the ISPC wheel's own self-test.

# --- ISPC wheel: PrimeISPC/solution_1 (hc/idea1-affinity), as its Dockerfile builds it -----
FROM ubuntu:24.04 AS ispc

RUN apt-get update \
    && apt-get install -y --no-install-recommends ispc gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/app
ARG ISPC_TARGETS
COPY ispc/primes.ispc ispc/build.sh ./
RUN sh build.sh && ispc --version > ispc-version.txt

# --- Zig wheel: PrimeZig/solution_4 (hc/zig-submission), as its Dockerfile builds it --------
# build.sh produces the submission binary (stripped). A second binary with the same flags but
# no -fstrip keeps the symbol table for objdump; dump.sh checks that each dumped function's
# instruction sequence also occurs in the stripped binary.
FROM alpine:3.21 AS zig

RUN apk add --no-cache zig=0.13.0-r1

WORKDIR /opt/app
ARG ZIG_CPU=native
COPY zig/primes.zig zig/build.sh ./
RUN sh build.sh \
    && zig build-exe primes.zig -O ReleaseFast -mcpu="${ZIG_CPU:-native}" -femit-bin=primes-sym \
    && zig version > zig-version.txt \
    && zig targets | awk '/"native"/,0' | head -200 > zig-native.txt

# --- Runtime: objdump over both binaries --------------------------------------------------
FROM ubuntu:24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends binutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/app
COPY --from=ispc /opt/app/primes ./ispc-primes
COPY --from=ispc /opt/app/ispc-version.txt ./
COPY --from=zig /opt/app/primes ./zig-primes
COPY --from=zig /opt/app/primes-sym ./zig-primes-sym
COPY --from=zig /opt/app/zig-version.txt /opt/app/zig-native.txt ./
COPY dump.sh ./dump.sh
RUN chmod +x ./dump.sh

ENTRYPOINT [ "./dump.sh" ]
