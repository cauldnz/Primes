# OxCaml toolchain image for the bench (RUN-PLAN run 10, phase 0). Not part of any submission.
# Built once per architecture on a Batch node by `hc-pool.sh submit <size> oxbuild`, saved with
# `docker save | zstd` to the bench storage account, and loaded by `ocaml` bench tasks.
# OxCaml needs glibc (no Alpine) and builds its own bootstrap OCaml, dune and menhir.
FROM ubuntu:24.04
ARG OPAM_VERSION=2.3.0
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      build-essential autoconf automake which git ca-certificates curl m4 unzip bzip2 rsync patch \
      pkg-config libgmp-dev zstd >/dev/null && rm -rf /var/lib/apt/lists/*
RUN arch=$(uname -m); case "$arch" in x86_64) a=x86_64;; aarch64) a=arm64;; esac; \
    curl -fsSL -o /usr/local/bin/opam "https://github.com/ocaml/opam/releases/download/${OPAM_VERSION}/opam-${OPAM_VERSION}-$a-linux" \
    && chmod +x /usr/local/bin/opam
ENV OPAMROOT=/opt/opam OPAMYES=1 OPAMCONFIRMLEVEL=unsafe-yes
RUN opam init --bare --disable-sandboxing -n -q
RUN start=$(date +%s); \
    opam switch create 5.2.0+ox --repos ox=git+https://github.com/oxcaml/opam-repository.git,default -q \
    && echo "switch build seconds: $(( $(date +%s) - start ))" | tee /opt/oxcaml-build-time.txt \
    && opam clean -a -c -s --logs -q
ENV OPAM_SWITCH_PREFIX=/opt/opam/5.2.0+ox PATH=/opt/opam/5.2.0+ox/bin:$PATH
RUN ocamlopt -version && ocamlopt -config | grep -E "^(architecture|flambda|version)" 
