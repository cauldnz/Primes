FROM alpine:3.21 AS build

RUN apk add --no-cache zig=0.13.0-r1

WORKDIR /opt/app
ARG ZIG_CPU=native
COPY primes.zig build.sh ./
RUN sh build.sh

FROM alpine:3.21

WORKDIR /opt/app
COPY --from=build /opt/app/primes .

ENTRYPOINT [ "./primes" ]
