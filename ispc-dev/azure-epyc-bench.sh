#!/usr/bin/env bash
# Benchmark the ISPC Primes solution against the current leaders on Azure AMD EPYC / Arm machines.
# Not part of the submission.
#
# Usage:  SUB=<subscription-id> [MODE=vm|batch] ./azure-epyc-bench.sh <vm-size> [vm-size ...]
#   e.g. Standard_D16as_v5 (EPYC Zen 3, AVX2 only), Standard_D16as_v6 (Zen 4), Standard_D16as_v7
#        (Zen 5), Standard_D4ps_v5 (Ampere Altra, arm64), Standard_D4ps_v6 (Cobalt 100, arm64).
# Common env: SUB (required: every az call is pinned to it), BASE (git ref for the "old" /
#   champion build), OUT (results folder; default results/azure-<timestamp>), SUITE:
#   default  new/old/forced-AVX2 vs C5/Chapel, plus a threshold sweep (solution_1)
#   targets  ISPC_TARGETS matrix for both entries vs C5/Rust/Chapel
#   ab       hill-climbing A/B for ENTRY=1|2 (default 1): candidate = working tree, champion =
#            BASE, champion run twice per round (A/A noise floor) plus a control (C5 for the
#            wheel on x86, mike-barber Rust otherwise); one discarded warm-up round, then
#            ROUNDS (default 5) rounds in random order. Analyse with ispc-dev/analyze.py.
# Every pool/VM run appends "date,mode,size,minutes" to results/cost-log.csv.
#
# MODE=vm (default): one VM per size, driven over SSH.
#   Env: LOCATION (resource group), REGIONS (VM regions to try in order; default LOCATION),
#        PRIORITY (Spot|Regular; some subscription offers cannot use Spot VMs).
#   Every VM lives in one resource group that is deleted at the end (also on Ctrl-C), and each
#   VM gets an Azure auto-shutdown 2 hours out as a backstop.
#
# MODE=batch: one Azure Batch pool of Spot nodes per size (Batch service mode, so Spot works on
#   any subscription offer and the account's own quota applies).
#   Env: BATCH_ACCOUNT and BATCH_RG (required; tools/azure-setup.sh writes them),
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
BATCH_ACCOUNT="${BATCH_ACCOUNT:?set BATCH_ACCOUNT (tools/azure-setup.sh writes it)}"
BATCH_RG="${BATCH_RG:?set BATCH_RG (tools/azure-setup.sh writes it)}"
NODES="${NODES:-1}"
MAX_MINUTES="${MAX_MINUTES:-90}"
[ $# -gt 0 ] || { echo "usage: $0 <vm-size> [vm-size ...]" >&2; exit 2; }
SIZES=("$@")
HERE="$(cd "$(dirname "$0")" && pwd)"
SOLUTION="$HERE/../PrimeISPC/solution_1"
OUT="${OUT:-$HERE/results/azure-$(date +%Y%m%d%H%M)}"
mkdir -p "$OUT"
COSTLOG="$HERE/results/cost-log.csv"
KEYDIR="$(mktemp -d)"
ENTRY="${ENTRY:-1}"
ROUNDS="${ROUNDS:-5}"
case "$ENTRY" in 1|2) ;; *) echo "ENTRY must be 1 or 2" >&2; exit 2;; esac

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
# SUITE=ab: candidate = working tree of PrimeISPC/solution_$ENTRY, champion = the same folder at BASE.
mkdir -p "$STAGE/cand" "$STAGE/champ"
for f in "$HERE/../PrimeISPC/solution_$ENTRY/"*; do sed 's/\r$//' "$f" > "$STAGE/cand/$(basename "$f")"; done
for f in $(git -C "$HERE/.." ls-tree --name-only "$BASE" "PrimeISPC/solution_$ENTRY/"); do
  git -C "$HERE/.." show "$BASE:$f" > "$STAGE/champ/$(basename "$f")"
done
[ -f "$STAGE/champ/Dockerfile" ] || { echo "!!! no PrimeISPC/solution_$ENTRY at $BASE"; exit 1; }
if [ "${SUITE:-default}" = ab ] && diff -rq "$STAGE/cand" "$STAGE/champ" >/dev/null; then
  echo "!!! candidate equals champion (BASE=$BASE): commit the candidate elsewhere or set BASE"; exit 1
fi
# SUITE=profile: TSC-instrumented builds of the base entry and of mike-barber's Rust.
mkdir -p "$STAGE/baseprof" "$STAGE/rustprof"
cp "$STAGE/base/Dockerfile" "$STAGE/base/build.sh" "$STAGE/baseprof/"
sed 's/\r$//' "$HERE/prototypes/profile/base_prof.ispc" > "$STAGE/baseprof/primes_base.ispc"
sed 's/\r$//' "$HERE/prototypes/profile/rust_prof_main.rs" > "$STAGE/rustprof/main.rs"
cost() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$MODE,$1,$2" >> "$COSTLOG"; }

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

# SUITE=ab: candidate vs champion vs champion again (A/A) vs a control, warm-up round discarded,
# then $ROUNDS rounds with the order shuffled each round. Labels: cand, champ, champ2, ctrl.
REMOTE_AB='
set -e
STAGE="${STAGE:-$HOME/stage}"
export DEBIAN_FRONTEND=noninteractive DOCKER_BUILDKIT=1
APT="sudo apt-get -o DPkg::Lock::Timeout=600 -qq"
$APT update && $APT install -y docker.io docker-buildx git >/dev/null
lscpu | grep -E "Model name|^CPU\(s\)|^Architecture" || true
grep -q avx512f /proc/cpuinfo && echo "AVX-512: yes" || echo "AVX-512: no"
echo "entry=$ENTRY rounds=$ROUNDS"
git clone -q --depth 1 -b drag-race https://github.com/PlummersSoftwareLLC/Primes.git
cd Primes
build() { echo "build $2"; sudo docker build -q -t "$2" "$1" >/dev/null || { echo "!!! build $2 failed"; exit 3; }; }
build "$STAGE/cand" cand
build "$STAGE/champ" champ
if [ "$(uname -m)" = x86_64 ] && [ "$ENTRY" = 1 ]; then build PrimeC/solution_5 ctrl; CTRL="rogiervandam_extend"
else build PrimeRust/solution_1 ctrl; CTRL="mike-barber_bit-extreme-hybrid"; fi
echo "control=$CTRL"
for i in cand champ; do
  r=$(sudo docker run --rm -e PRIMES_TEST=1 "$i" 2>&1; echo "exit=$?")
  echo "self-test $i: $(echo "$r" | grep -c " 1$") ok, $(echo "$r" | grep -c " 0$") bad, $(echo "$r" | tail -1)"
  echo "$r" | tail -1 | grep -q "exit=0" || { echo "!!! self-test $i failed"; exit 4; }
done
img() { case $1 in champ2) echo champ;; *) echo $1;; esac; }
one() { echo "== round $1 $2"; sudo docker run --rm "$(img $2)" 2>/dev/null | grep ";" \
          | { [ "$2" = ctrl ] && grep -E "^${CTRL}(_epar)?;" || cat; } || echo "!!! run $2 failed"; }
for x in cand champ champ2 ctrl; do one warmup $x; done
for i in $(seq "$ROUNDS"); do
  for x in $(printf "cand\nchamp\nchamp2\nctrl\n" | shuf); do one "$i" $x; done
done
'
# SUITE=profile: perf on the host (the task runs as root). Each image is exported to a root
# filesystem and its binary runs under chroot, so perf needs no container privileges and
# resolves symbols with --symfs. 1T only: timeout stops our two-phase binaries after the 1T run.
# Entries: our wheel (new = working tree), our base, C5, Rust; then the TSC phase builds.
REMOTE_PROFILE='
set -e
STAGE="${STAGE:-$HOME/stage}"
export DEBIAN_FRONTEND=noninteractive DOCKER_BUILDKIT=1
APT="sudo apt-get -o DPkg::Lock::Timeout=600 -qq"
$APT update && $APT install -y docker.io docker-buildx git >/dev/null
$APT install -y linux-tools-$(uname -r) linux-tools-generic >/dev/null 2>&1 || $APT install -y linux-tools-generic >/dev/null 2>&1 || true
PERF=$(ls /usr/lib/linux-tools/*/perf 2>/dev/null | head -1); [ -x "$PERF" ] || PERF=perf
echo "perf: $PERF ($($PERF --version 2>&1))"; echo "kernel: $(uname -r)"
sysctl -w kernel.perf_event_paranoid=-1 kernel.kptr_restrict=0 >/dev/null
lscpu | grep -E "Model name|^CPU\(s\)|^Architecture" || true
grep -q avx512f /proc/cpuinfo && echo "AVX-512: yes" || echo "AVX-512: no"
git clone -q --depth 1 -b drag-race https://github.com/PlummersSoftwareLLC/Primes.git
cd Primes
cp -r PrimeRust/solution_1 "$STAGE/rustprof/src"; cp "$STAGE/rustprof/main.rs" "$STAGE/rustprof/src/prime-sieve-rust/src/main.rs"
build() { echo "build $2"; docker build -q -t "$2" "$1" >/dev/null || echo "!!! build $2 failed"; }
build "$STAGE/new" wheel; build "$STAGE/base" base; build PrimeC/solution_5 c5
build PrimeRust/solution_1 rust; build "$STAGE/baseprof" baseprof; build "$STAGE/rustprof/src" rustprof
for i in wheel base c5 rust; do
  mkdir -p /rf/$i; cid=$(docker create $i); docker export $cid | tar x -C /rf/$i; docker rm $cid >/dev/null
  mount -t proc proc /rf/$i/proc; mount --bind /sys /rf/$i/sys
done
echo "== counters"; $PERF stat -e cycles,instructions,branches,branch-misses,L1-dcache-loads,L1-dcache-load-misses true 2>&1 | grep -E "cycles|instructions|branch|L1|supported" || true
EV=""; $PERF stat -e cycles true 2>&1 | grep -q "not supported\|<not" && EV="-e cpu-clock" && echo "hardware cycles not available: sampling cpu-clock"
cmd() { case $1 in
  wheel|base) echo "cd /opt/app && exec ./primes";;
  c5) echo "cd /home/sieve && LD_PRELOAD=/usr/lib/libmimalloc.so exec bin/sieve_extend";;
  rust) echo "cd /app && exec ./prime-sieve-rust --bits-extreme -t 1";; esac; }
for i in wheel base c5 rust; do
  echo "=== perf stat $i"
  timeout -s INT 5.6 $PERF stat -d -- chroot /rf/$i /bin/sh -c "$(cmd $i)" 2>&1 | grep -vE "^$" | tail -40 || true
  echo "=== perf record $i"
  timeout -s INT 5.6 $PERF record $EV -g -o /root/$i.data -- chroot /rf/$i /bin/sh -c "$(cmd $i)" 2>&1 | grep ";" || true
  echo "--- report $i (self, by symbol)"
  $PERF report -i /root/$i.data --symfs=/rf/$i --no-children --stdio -g none --sort dso,sym 2>/dev/null | grep -vE "^#|^$" | head -25
  TOP=$($PERF report -i /root/$i.data --symfs=/rf/$i --no-children --stdio -g none --sort sym -F sym 2>/dev/null | grep -vE "^#|^$" | head -1 | sed "s/^ *\[[^]]*\] *//")
  echo "--- annotate $i: $TOP (lines >= 0.5%)"
  $PERF annotate -i /root/$i.data --symfs=/rf/$i --stdio "$TOP" 2>/dev/null | awk -F: "\$1+0 >= 0.5" | head -120 || true
done
echo "=== TSC phase builds"
for r in 1 2 3; do
  echo "== round $r baseprof"; docker run --rm baseprof 2>&1 | grep -E "PROF|^F |;" || true
  echo "== round $r rustprof"; docker run --rm rustprof --bits-extreme -t 1 2>&1 | grep -E "PROF|^F |;" || true
done
'
case "${SUITE:-default}" in
  default) ;;
  profile) REMOTE_SCRIPT="$REMOTE_PROFILE" ;;
  targets) REMOTE_SCRIPT="$REMOTE_TARGETS" ;;
  ab) REMOTE_SCRIPT="export ENTRY=$ENTRY ROUNDS=$ROUNDS
$REMOTE_AB" ;;
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
    echo "  created in $CREATED $(date +%T)"; T_VM=$(date +%s)
    azs vm auto-shutdown -g "$RG" -n "$VM" --time "$(date -u -d '+2 hours' +%H%M)" -o none || true
    IP=$(azs vm show -d -g "$RG" -n "$VM" --query publicIps -o tsv)
    for _ in $(seq 20); do ssh "${SSHOPTS[@]}" "azureuser@$IP" true 2>/dev/null && break; sleep 6; done
    scp "${SSHOPTS[@]}" -r "$STAGE" "azureuser@$IP:~/"
    ssh "${SSHOPTS[@]}" "azureuser@$IP" "bash -s" <<< "$REMOTE_SCRIPT" | tee "$OUT/$SIZE.txt" || true
    echo "### done $SIZE $(date +%T), deleting VM"
    azs vm delete -g "$RG" -n "$VM" --yes -o none || true   # stop paying as soon as it's done
    cost "$SIZE" $(( ( $(date +%s) - T_VM ) / 60 + 1 ))
  done

# ---------------------------------------------------------------------------------------------
elif [ "$MODE" = batch ]; then
  TAG="primes-$(date +%Y%m%d%H%M%S)"
  POOLS=()
  # Shared-key auth: needs only management-plane access to the account (e.g. Contributor on its
  # resource group), so a scoped service principal works without a Batch data-plane role.
  azs batch account login -n "$BATCH_ACCOUNT" -g "$BATCH_RG" --shared-key-auth -o none
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
    POOLS+=("$P"); T_POOL=$(date +%s)
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
    cost "$SIZE" $(( ( $(date +%s) - T_POOL ) / 60 + 1 ))
  done
else
  echo "unknown MODE=$MODE" >&2; exit 2
fi

echo "Results in $OUT"
