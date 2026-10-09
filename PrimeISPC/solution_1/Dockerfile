FROM ubuntu:24.04 AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends ispc gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/app
COPY primes.ispc build.sh ./
RUN sh build.sh

FROM ubuntu:24.04

WORKDIR /opt/app
COPY --from=build /opt/app/primes .

ENTRYPOINT [ "./primes" ]
