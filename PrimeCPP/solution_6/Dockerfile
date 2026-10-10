FROM ubuntu:24.04 AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends g++ libc6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/app
COPY primes.cpp .
RUN g++ -std=c++20 -O3 -march=native -pthread primes.cpp -o primes

FROM ubuntu:24.04

WORKDIR /opt/app
COPY --from=build /opt/app/primes .

ENTRYPOINT [ "./primes" ]
