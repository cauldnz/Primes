#!/usr/bin/env bash
# Benchmark the ISPC Primes solution against the current leaders on Azure AMD EPYC / Arm machines.
# Not part of the submission.
#
# Usage:  SUB=<subscription-id> [MODE=vm|batch] ./azure-epyc-bench.sh <vm-size> [vm-size ...]
#   e.g. Standard_D16as_v5 (EPYC Zen 3, AVX2 only), Standard_D16as_v6 (Zen 4), Standard_D16as_v7
#        (Zen 5), Standard_D4ps_v5 (Ampere Altra, arm64), Standard_D4ps_v6 (Cobalt 100, arm64).
# Common env: SUB (required: every az call is pinned to it), BASE (git ref for the "old" build),
#   SUITE (default: new/old/AVX2 vs C5/Chapel; targets: ISPC_TARGETS matrix for both entries).
#
# MODE=vm (default): one VM per size, driven over SSH.
#   Env: LOCATION (resource group), REGIONS (VM regions to try in order; default LOCATION),
#        PRIORITY (Spot|Regular; Visual Studio subscriptions cannot use Spot VMs).
#   Every VM lives in one resource group that is deleted at the end (also on Ctrl-C), and each
#   VM gets an Azure auto-shutdown 2 hours out as a backstop.
#
# MODE=batch: one Azure Batch pool of Spot nodes per size (Batch service mode, so Spot works on
#   any subscription offer and the account's own quota applies).
#   Env: BATCH_ACCOUNT (default batchllmwestus2gves), BATCH_RG (default rg-chris-batch-llm),
#        NODES (default 1), MAX_MINUTES (hard cap per pool, default 90).
#   Three layers stop runaway cost: the pool, job and uploaded blob are deleted on exit (also on
#   Ctrl-C); the pool's autoscale formula targets 0 nodes after a fixed deadline, so Azure scales
#   it down even if this script dies; the task has a wall-clock limit.
#
# Requires: az CLI logged in; ssh (vm mode); python, tar (batch mode).
set -euo pipefail

: "${SUB:?set SUB to the subscription id}"
MODE="${MODE:-vm}"
LOCATION="${LOCATION:-australiaeast}"
PRIORITY="${PRIORITY:-Spot}"
RG="${RG:-primes-bench-$(date +%Y%m%d%H%M)}"
BATCH_ACCOUNT="${BATCH_ACCOUNT:-batchllmwestus2gves}"
BATCH_RG="${BATCH_RG:-rg-chris-batch-llm}"
NODES="${NODES:-1}"
MAX_MINUTES="${MAX_MINUTES:-90}"
[ $# -gt 0 ] || { echo "usage: $0 <vm-size> [vm-size ...]" >&2; exit 2; }
SIZES=("$@")
HERE="$(cd "$(dirname "$0")" && pwd)"
SOLUTION="$HERE/../PrimeISPC/solution_1"
OUT="$HERE/results/azure-$(date +%Y%m%d%H%M)"
mkdir -p "$OUT"
KEYDIR="$(mktemp -d)"

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
# The base-algorithm entry (solution_2), for SUITE=targets.
mkdir -p "$STAGE/base"
for f in "$HERE/../PrimeISPC/solution_2/"*; do sed 's/\r$//' "$f" > "$STAGE/base/$(basename "$f")"; done
sed -i '/^set -e$/a ISPC_TARGETS=avx2-i32x8' "$STAGE/avx2/build.sh"
grep -q '^ISPC_TARGETS=avx2-i32x8$' "$STAGE/avx2/build.sh" || { echo "!!! could not force AVX2 target"; exit 1; }

azs() { az "$@" --subscription "$SUB"; }
is_arm() { case "$1" in Standard_[A-Z]*[0-9]p*_v*) return 0;; *) return 1;; esac; }

# Runs on each machine: install Docker with BuildKit (the legacy builder breaks PrimeC/solution_5,
# whose build step sees /.dockerenv and skips compiling), fetch upstream drag-race, build our
# variants and the leaders, interleave runs. On arm64 only our new/old builds run.
REMOTE_SCRIPT='
set -e
STAGE="${STAGE:-$HOME/stage}"
export DEBIAN_FRONTEND=noninteractive DOCKER_BUILDKIT=1
APT="sudo apt-get -o DPkg::Lock::Timeout=600 -qq"
$APT update && $APT install -y docker.io docker-buildx git >/dev/null
lscpu | grep -E "Model name|^CPU\(s\)|^Architecture" || true
grep -q avx512f /proc/cpuinfo && echo "AVX-512: yes" || echo "AVX-512: no"
git clone -q --depth 1 -b drag-race https://github.com/PlummersSoftwareLLC/Primes.git
cd Primes
build() { echo "build $2"; sudo docker build -q -t "$2" "$1" >/dev/null || echo "!!! build $2 failed"; }
run() { echo "== $1"; shift; sudo docker run --rm "$@" || echo "!!! run failed"; }
build "$STAGE/new" ispc
build "$STAGE/old" ispc-old
run "self-test new" -e PRIMES_TEST=1 ispc
if [ "$(uname -m)" = x86_64 ]; then
  build "$STAGE/avx2" ispc-avx2
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

# SUITE=targets: ISPC gang-width matrix for the wheel entry (solution_1) and the base entry
# (solution_2), each built with --build-arg ISPC_TARGETS, against C5, Rust and Chapel.
REMOTE_TARGETS='
set -e
STAGE="${STAGE:-$HOME/stage}"
export DEBIAN_FRONTEND=noninteractive DOCKER_BUILDKIT=1
APT="sudo apt-get -o DPkg::Lock::Timeout=600 -qq"
$APT update && $APT install -y docker.io docker-buildx git >/dev/null
lscpu | grep -E "Model name|^CPU\(s\)|^Architecture" || true
AVX512=no; grep -q avx512f /proc/cpuinfo && AVX512=yes; echo "AVX-512: $AVX512"
git clone -q --depth 1 -b drag-race https://github.com/PlummersSoftwareLLC/Primes.git
cd Primes
IMGS=""
bt() { echo "build $2 [${3:-default}]"; sudo docker build -q --build-arg ISPC_TARGETS="$3" -t "$2" "$1" >/dev/null \
         && IMGS="$IMGS $2" || echo "!!! build $2 failed"; }
build() { echo "build $2"; sudo docker build -q -t "$2" "$1" >/dev/null || echo "!!! build $2 failed"; }
run() { echo "== $1"; shift; sudo docker run --rm "$@" 2>&1 | grep ";" || echo "!!! run failed"; }
selftest() { for i in $IMGS; do
  r=$(sudo docker run --rm -e PRIMES_TEST=1 "$i" 2>&1; echo "exit=$?")
  echo "self-test $i: $(echo "$r" | grep -c " 1$") ok, $(echo "$r" | grep -c " 0$") bad, $(echo "$r" | tail -1)"; done; }
if [ "$(uname -m)" = x86_64 ]; then
  bt "$STAGE/new" w-default ""
  bt "$STAGE/new" w-avx2x8 avx2-i32x8
  bt "$STAGE/new" w-avx2x16 avx2-i32x16
  if [ $AVX512 = yes ]; then bt "$STAGE/new" w-avx512x8 avx512skx-x8; bt "$STAGE/new" w-avx512x16 avx512skx-x16; fi
  bt "$STAGE/base" b-default ""
  [ $AVX512 = yes ] && bt "$STAGE/base" b-avx512 "sse4-i32x4,avx2-i32x8,avx512skx-x16"
  build PrimeC/solution_5 c5
  build PrimeRust/solution_1 rust
  build PrimeChapel/solution_1 chapel
  selftest
  for i in 1 2 3; do
    for w in $IMGS; do case $w in w-*) run "round $i $w" $w;; esac; done
    run "round $i C5" c5
    for b in $IMGS; do case $b in b-*) run "round $i $b" $b;; esac; done
    run "round $i Rust" rust
    run "round $i Chapel" chapel
  done
  for d in 192 256 320; do run "DENSE_MAX=$d w-default" -e PRIMES_DENSE_MAX=$d w-default; done
else
  bt "$STAGE/new" w-default ""
  bt "$STAGE/new" w-neonx8 neon-i32x8
  bt "$STAGE/base" b-default ""
  build PrimeRust/solution_1 rust
  selftest
  for i in 1 2 3; do
    run "round $i w-default" w-default; run "round $i w-neonx8" w-neonx8
    run "round $i b-default" b-default; run "round $i Rust" rust
  done
fi
'
case "${SUITE:-default}" in
  default) ;;
  targets) REMOTE_SCRIPT="$REMOTE_TARGETS" ;;
  *) echo "unknown SUITE=$SUITE" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------------------------
if [ "$MODE" = vm ]; then
  ssh-keygen -q -t ed25519 -N "" -f "$KEYDIR/id" -C primes-bench
  SSHOPTS=(-i "$KEYDIR/id" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ServerAliveInterval=30)
  cleanup() {
    echo "Deleting resource group $RG (waits until gone)"
    azs group delete -n "$RG" --yes || echo "!!! group delete failed: check 'az group list' NOW"
    rm -rf "$KEYDIR"
  }
  trap cleanup EXIT
  azs group create -n "$RG" -l "$LOCATION" -o none
  SPOT=()
  [ "$PRIORITY" = Spot ] && SPOT=(--priority Spot --eviction-policy Delete --max-price -1)

  for SIZE in "${SIZES[@]}"; do
    VM="primes-${SIZE//_/-}"; VM="${VM,,}"; VM="${VM:0:40}"
    echo "### $SIZE ($PRIORITY) $(date +%T)"
    NVME=(); case "$SIZE" in *_v6|*_v7) NVME=(--disk-controller-type NVMe);; esac   # v6+ are NVMe-only
    IMAGE=Ubuntu2404; is_arm "$SIZE" && IMAGE=Canonical:ubuntu-24_04-lts:server-arm64:latest
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

# ---------------------------------------------------------------------------------------------
elif [ "$MODE" = batch ]; then
  TAG="primes-$(date +%Y%m%d%H%M%S)"
  POOLS=()
  azs batch account login -n "$BATCH_ACCOUNT" -g "$BATCH_RG" -o none
  SA=$(azs batch account show -n "$BATCH_ACCOUNT" -g "$BATCH_RG" --query autoStorage.storageAccountId -o tsv)
  SA="${SA##*/}"
  [ -n "$SA" ] || { echo "!!! Batch account has no linked storage"; exit 1; }
  SAKEY=$(azs storage account keys list -n "$SA" --query "[0].value" -o tsv)
  st() { az storage "$@" --account-name "$SA" --account-key "$SAKEY"; }

  cleanup() {
    for P in "${POOLS[@]}"; do
      echo "Deleting job and pool $P"
      az batch job delete --job-id "$P" --yes 2>/dev/null || true
      az batch pool delete --pool-id "$P" --yes 2>/dev/null || true
    done
    st blob delete -c primes-bench -n "$TAG.tgz" -o none 2>/dev/null || true
    for P in "${POOLS[@]}"; do   # wait until the pool (and its nodes) are really gone
      for _ in $(seq 60); do az batch pool show --pool-id "$P" -o none 2>/dev/null || break; sleep 10; done
      az batch pool show --pool-id "$P" -o none 2>/dev/null \
        && echo "!!! pool $P still exists: check 'az batch pool list' NOW" || echo "pool $P gone"
    done
    rm -rf "$KEYDIR"
  }
  trap cleanup EXIT

  # Ship the staged builds plus the benchmark script to the node through the linked storage
  # account, read-only SAS link valid for 4 hours.
  printf '%s' "$REMOTE_SCRIPT" > "$STAGE/run.sh"
  tar czf "$KEYDIR/$TAG.tgz" -C "$KEYDIR" stage
  st container create -n primes-bench -o none
  st blob upload -c primes-bench -n "$TAG.tgz" -f "$KEYDIR/$TAG.tgz" --overwrite -o none
  URL=$(st blob generate-sas -c primes-bench -n "$TAG.tgz" --permissions r \
        --expiry "$(date -u -d '+4 hours' +%Y-%m-%dT%H:%MZ)" --https-only --full-uri -o tsv)

  for SIZE in "${SIZES[@]}"; do
    P="$TAG-${SIZE,,}"; P="${P//_/-}"; P="${P:0:64}"
    echo "### $SIZE (Batch Spot x$NODES, cap ${MAX_MINUTES}m) $(date +%T)"
    if is_arm "$SIZE"; then SKU=server-arm64; AGENT="batch.node.ubuntu 24.04-arm64"
    else SKU=server; AGENT="batch.node.ubuntu 24.04"; fi
    DEADLINE=$(date -u -d "+$MAX_MINUTES minutes" +%Y-%m-%dT%H:%M:%SZ)
    python - "$P" "$SIZE" "$SKU" "$AGENT" "$NODES" "$DEADLINE" "$URL" "$MAX_MINUTES" "$KEYDIR" <<'PY'
import json, sys
pool, size, sku, agent, nodes, deadline, url, cap, d = sys.argv[1:]
formula = (f'$TargetLowPriorityNodes = time() < time("{deadline}") ? {nodes} : 0;\n'
           '$TargetDedicatedNodes = 0;\n$NodeDeallocationOption = terminate;')
json.dump({"id": pool, "vmSize": size, "taskSlotsPerNode": 1,
           "virtualMachineConfiguration": {
               "imageReference": {"publisher": "canonical", "offer": "ubuntu-24_04-lts",
                                  "sku": sku, "version": "latest"},
               "nodeAgentSKUId": agent},
           "enableAutoScale": True, "autoScaleFormula": formula,
           "autoScaleEvaluationInterval": "PT5M"}, open(f"{d}/pool.json", "w"))
json.dump({"id": pool, "poolInfo": {"poolId": pool}, "onAllTasksComplete": "terminatejob"},
          open(f"{d}/job.json", "w"))
json.dump({"id": "bench",
           "commandLine": "/bin/bash -c 'tar xzf stage.tgz && STAGE=$AZ_BATCH_TASK_WORKING_DIR/stage bash stage/run.sh'",
           "resourceFiles": [{"httpUrl": url, "filePath": "stage.tgz"}],
           "userIdentity": {"autoUser": {"scope": "pool", "elevationLevel": "admin"}},
           "constraints": {"maxWallClockTime": f"PT{max(10, int(cap) - 10)}M", "maxTaskRetryCount": 0}},
          open(f"{d}/task.json", "w"))
PY
    if ! az batch pool create --json-file "$KEYDIR/pool.json" 2>"$OUT/$SIZE-pool.err"; then
      echo "!!! pool create failed:"; tail -3 "$OUT/$SIZE-pool.err"; continue
    fi
    POOLS+=("$P")
    az batch job create --json-file "$KEYDIR/job.json" -o none
    az batch task create --job-id "$P" --json-file "$KEYDIR/task.json" -o none

    # Follow the task, copying its stdout into results/ as it grows.
    SHOWN=0; T0=$(date +%s); LAST=
    while :; do
      STATE=$(az batch task show --job-id "$P" --task-id bench --query state -o tsv 2>/dev/null || echo unknown)
      ALLOC=$(az batch pool show --pool-id "$P" --query "join(' ', [allocationState, to_string(currentLowPriorityNodes)])" -o tsv 2>/dev/null || true)
      RERR=$(az batch pool show --pool-id "$P" --query "resizeErrors[0].code" -o tsv 2>/dev/null || true)
      [ "$STATE $ALLOC" != "$LAST" ] && { echo "  $(date +%T) task=$STATE pool=$ALLOC"; LAST="$STATE $ALLOC"; }
      if [ "$STATE" = running ] || [ "$STATE" = completed ]; then
        # download refuses to overwrite an existing file: fetch into a fresh temp file, then replace
        rm -f "$KEYDIR/stdout.part"
        if az batch task file download --job-id "$P" --task-id bench --file-path stdout.txt \
             --destination "$KEYDIR/stdout.part" 2>/dev/null && mv -f "$KEYDIR/stdout.part" "$OUT/$SIZE.txt"; then
          N=$(wc -l < "$OUT/$SIZE.txt"); [ "$N" -gt "$SHOWN" ] && tail -n +$((SHOWN + 1)) "$OUT/$SIZE.txt"; SHOWN=$N
        fi
      fi
      [ "$STATE" = completed ] && break
      if [ -n "$RERR" ] && [ "$STATE" != running ]; then
        echo "!!! allocation problem: $RERR"
        az batch pool show --pool-id "$P" --query "resizeErrors[].message" -o tsv; break
      fi
      [ $(( $(date +%s) - T0 )) -gt $(( MAX_MINUTES * 60 )) ] && { echo "!!! hit ${MAX_MINUTES}m cap"; break; }
      sleep 30
    done
    rm -f "$OUT/$SIZE-stderr.txt"
    az batch task file download --job-id "$P" --task-id bench --file-path stderr.txt \
       --destination "$OUT/$SIZE-stderr.txt" 2>/dev/null || true
    az batch task show --job-id "$P" --task-id bench --query "executionInfo.{exit:exitCode,result:result,failure:failureInfo.message}" -o json 2>/dev/null || true
    echo "### done $SIZE $(date +%T), deleting pool"
    az batch job delete --job-id "$P" --yes 2>/dev/null || true
    az batch pool delete --pool-id "$P" --yes 2>/dev/null || true   # stop paying as soon as it's done
  done
else
  echo "unknown MODE=$MODE" >&2; exit 2
fi

echo "Results in $OUT"
