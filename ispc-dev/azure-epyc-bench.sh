#!/usr/bin/env bash
# Benchmark the ISPC Primes solution against the current leaders on Azure AMD EPYC VMs.
# Not part of the submission.
#
# Usage:  SUB=<subscription-id> ./azure-epyc-bench.sh [vm-size ...]
#   e.g. Standard_D16as_v5 (EPYC Zen 3, AVX2 only), Standard_D16as_v7 (EPYC Zen 5, AVX-512),
#        Standard_D4ps_v5 (Ampere Altra, arm64). Env BASE: git ref for the "old" build.
# Env: SUB (required: every az call is pinned to it), LOCATION (resource group),
#      REGIONS (space-separated VM regions to try in order; default LOCATION), PRIORITY (Spot|Regular).
# Requires: az CLI logged in, ssh. Run from anywhere; uses ../PrimeISPC/solution_1.
# Every VM lives in one resource group that is deleted at the end (also on Ctrl-C).
# Spot VMs use eviction policy Delete; each VM also gets an Azure auto-shutdown as a
# backstop in case this script dies before cleanup.
set -euo pipefail

: "${SUB:?set SUB to the subscription id}"
LOCATION="${LOCATION:-australiaeast}"
PRIORITY="${PRIORITY:-Spot}"
RG="${RG:-primes-bench-$(date +%Y%m%d%H%M)}"
SIZES=("${@:-Standard_D32as_v5 Standard_D32as_v6}")
read -r -a SIZES <<< "${SIZES[*]}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SOLUTION="$HERE/../PrimeISPC/solution_1"
OUT="$HERE/results/azure-$(date +%Y%m%d%H%M)"
mkdir -p "$OUT"
KEYDIR="$(mktemp -d)"
ssh-keygen -q -t ed25519 -N "" -f "$KEYDIR/id" -C primes-bench
# Stage three variants, LF-only (a Windows checkout with core.autocrlf has CRLF, which breaks
# build.sh): new = working tree, old = $BASE (default HEAD) for interleaved A/B,
# avx2 = working tree forced to the AVX2 target only (what an AVX-512-less EPYC runs).
BASE="${BASE:-HEAD}"
STAGE="$KEYDIR/stage"; mkdir -p "$STAGE/new" "$STAGE/old" "$STAGE/avx2"
for f in Dockerfile build.sh primes.ispc; do
  sed 's/\r$//' "$SOLUTION/$f" > "$STAGE/new/$f"
  git -C "$HERE/.." show "$BASE:PrimeISPC/solution_1/$f" > "$STAGE/old/$f"
done
cp "$STAGE/new/"* "$STAGE/avx2/"
sed -i 's/TARGETS="sse4-i32x4,avx2-i32x8,avx512skx-x16"/TARGETS="avx2-i32x8"/' "$STAGE/avx2/build.sh"
grep -q 'TARGETS="avx2-i32x8"' "$STAGE/avx2/build.sh" || { echo "!!! could not force AVX2 target"; exit 1; }
SSHOPTS=(-i "$KEYDIR/id" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ServerAliveInterval=30)

azs() { az "$@" --subscription "$SUB"; }

cleanup() {
  echo "Deleting resource group $RG (waits until gone)"
  azs group delete -n "$RG" --yes || echo "!!! group delete failed: check 'az group list' NOW"
  rm -rf "$KEYDIR"
}
trap cleanup EXIT

azs group create -n "$RG" -l "$LOCATION" -o none

SPOT=()
[ "$PRIORITY" = Spot ] && SPOT=(--priority Spot --eviction-policy Delete --max-price -1)

# Runs on each VM: install Docker with BuildKit (the legacy builder breaks PrimeC/solution_5,
# whose build step sees /.dockerenv and skips compiling), fetch upstream drag-race, build our
# variants and the leaders, interleave runs. On arm64 only our new/old builds run.
REMOTE_SCRIPT='
set -e
export DEBIAN_FRONTEND=noninteractive DOCKER_BUILDKIT=1
sudo apt-get update -qq && sudo apt-get install -y -qq docker.io docker-buildx git >/dev/null
lscpu | grep -E "Model name|^CPU\(s\)|^Architecture" || true
grep -q avx512f /proc/cpuinfo && echo "AVX-512: yes" || echo "AVX-512: no"
git clone -q --depth 1 -b drag-race https://github.com/PlummersSoftwareLLC/Primes.git
cd Primes
build() { echo "build $2"; sudo docker build -q -t "$2" "$1" >/dev/null || echo "!!! build $2 failed"; }
run() { echo "== $1"; shift; sudo docker run --rm "$@" || echo "!!! run failed"; }
build ~/stage/new ispc
build ~/stage/old ispc-old
run "self-test new" -e PRIMES_TEST=1 ispc
if [ "$(uname -m)" = x86_64 ]; then
  build ~/stage/avx2 ispc-avx2
  build PrimeC/solution_5 c5
  build PrimeChapel/solution_1 chapel
  build PrimeC/solution_2 c2
  run "self-test avx2" -e PRIMES_TEST=1 ispc-avx2
  for i in 1 2 3; do
    run "round $i new" ispc; run "round $i old" ispc-old; run "round $i avx2" ispc-avx2
    run "round $i C5" c5; run "round $i Chapel" chapel
  done
  echo "== C2"; sudo docker run --rm c2 | grep -E "5760of30030|480of2310" || true
  for d in 192 224 256 288; do
    run "DENSE_MAX=$d new" -e PRIMES_DENSE_MAX=$d ispc
    run "DENSE_MAX=$d avx2" -e PRIMES_DENSE_MAX=$d ispc-avx2
  done
else
  for i in 1 2 3; do run "round $i new" ispc; run "round $i old" ispc-old; done
  for d in 128 192 256 384; do run "DENSE_MAX=$d new" -e PRIMES_DENSE_MAX=$d ispc; done
fi
'

for SIZE in "${SIZES[@]}"; do
  VM="primes-${SIZE//_/-}"; VM="${VM,,}"; VM="${VM:0:40}"
  echo "### $SIZE ($PRIORITY) $(date +%T)"
  NVME=(); case "$SIZE" in *_v6|*_v7) NVME=(--disk-controller-type NVMe);; esac   # v6+ are NVMe-only
  IMAGE=Ubuntu2404; case "$SIZE" in Standard_[A-Z]*[0-9]p*_v*) IMAGE=Canonical:ubuntu-24_04-lts:server-arm64:latest;; esac   # Arm sizes (D4ps_v5...)
  # Spot capacity comes and goes: try each candidate region until preflight accepts one.
  # A preflight failure creates nothing, so failed attempts cost nothing.
  CREATED=
  for LOC in ${REGIONS:-$LOCATION}; do
    echo "  trying $LOC"
    if azs vm create -g "$RG" -n "$VM" -l "$LOC" --image "$IMAGE" --size "$SIZE" "${SPOT[@]}" "${NVME[@]}" \
         --vnet-name "vnet-$LOC" --nsg "nsg-$LOC" --public-ip-address "ip-$LOC" \
         --admin-username azureuser --ssh-key-values "$KEYDIR/id.pub" \
         --public-ip-sku Standard --nsg-rule SSH -o none 2>"$OUT/$SIZE-$LOC.err"; then
      CREATED=$LOC; break
    fi
    grep -oE "SkuNotAvailable|QuotaExceeded|OperationNotAllowed|NotAvailableForSubscription|[A-Za-z]+ is not supported[^.]*" "$OUT/$SIZE-$LOC.err" | sort -u | head -3
  done
  [ -n "$CREATED" ] || { echo "!!! could not create $SIZE anywhere, skipping"; continue; }
  echo "  created in $CREATED $(date +%T)"
  azs vm auto-shutdown -g "$RG" -n "$VM" --time "$(date -u -d '+2 hours' +%H%M)" -o none || true
  IP=$(azs vm show -d -g "$RG" -n "$VM" --query publicIps -o tsv)
  for _ in $(seq 20); do ssh "${SSHOPTS[@]}" "azureuser@$IP" true 2>/dev/null && break; sleep 6; done
  scp "${SSHOPTS[@]}" -r "$STAGE" "azureuser@$IP:~/"
  ssh "${SSHOPTS[@]}" "azureuser@$IP" "bash -s" <<< "$REMOTE_SCRIPT" | tee "$OUT/$SIZE.txt" || true
  echo "### done $SIZE $(date +%T), deleting VM"
  azs vm delete -g "$RG" -n "$VM" --yes -o none || true   # stop paying as soon as it's done
done

echo "Results in $OUT"
