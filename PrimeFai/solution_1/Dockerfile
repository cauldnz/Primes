FROM ubuntu:24.04 AS build

# Fai's release builds need glibc 2.35 or later; `fai build` links with `cc`.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

ARG FAI_VERSION=0.1.0
ENV FAI_HOME=/opt/fai
ENV PATH=/opt/fai/bin:$PATH
RUN curl -fsSLO https://github.com/Krzysztof-Cieslak/fai/releases/download/v${FAI_VERSION}/install.sh \
    && sh install.sh --version ${FAI_VERSION} --home /opt/fai --no-modify-path \
    && rm install.sh \
    && fai --version

WORKDIR /opt/app
COPY Primes.fai build.sh ./
RUN sh build.sh

FROM ubuntu:24.04
COPY --from=build /opt/app/primes /usr/local/bin/primes
ENTRYPOINT [ "/usr/local/bin/primes" ]
