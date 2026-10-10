# DIAGNOSTIC BUILD (hc/diag-swift-phases): never merge.
# Builds only upstream's PrimeSwift_1bitStriped_u8 package (with phase-timing
# instrumentation) using the same toolchain and compiler flags as upstream's
# PrimeSwift/solution_1/Dockerfile.
FROM swift:6.3.3 AS build

WORKDIR /opt/app

COPY . .

# On x86-64 the striped package targets Haswell (AVX2), as upstream does.
RUN if [ "$(uname -m)" = x86_64 ]; then set -- -Xswiftc -target-cpu -Xswiftc haswell; fi && \
    swift build -v --configuration release -Xswiftc -O -Xswiftc -whole-module-optimization "$@"

FROM swift:6.3.3-slim
WORKDIR /opt/app
COPY --from=build /opt/app/.build/release/PrimeSieveSwift ./PrimeSwift_1bitStriped_u8/.build/release/PrimeSieveSwift
COPY run.sh ./run.sh

ENTRYPOINT [ "./run.sh" ]
