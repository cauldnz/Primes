#!/usr/bin/env bash
# Persistent, auto-scaling Azure Batch pools for hill-climbing A/B runs. Not part of any submission.
#
# One pool per VM size lives for the whole run. Its autoscale formula follows the task queue
# (scale to the number of queued and running tasks, at most MAXNODES) and drops to 0 nodes when
# the queue is empty or a hard deadline passes. A start task installs Docker and builds the rival
# entries once per node: rogiervandam C5, mike-barber Rust and davepl C++ (x86), Rust and davepl
# (arm64). Each experiment is one task: it builds its own candidate and champion images, runs a
# warm-up round and ROUNDS shuffled rounds, and prints the same "== round <n> <label>" format as
# azure-epyc-bench.sh, so analyze.py reads it unchanged.
#
# Usage (needs SUB, az logged in; run from anywhere in the repo):
#   hc-pool.sh up <size> [maxnodes=2] [minutes=240]     create the pool (idempotent)
#   hc-pool.sh run <size> <kind> <cand-ref> <champ-ref> <outdir> [rounds=5]
#        kind: wheel | base | rust | zig. Submits one task and follows it until it completes,
#        copying its stdout to <outdir>/<size>.txt as it grows.
#   hc-pool.sh down <size>                              delete the pool and its job
#   hc-pool.sh status                                   list pools, nodes and tasks
#   FLOOR=1 hc-pool.sh floor <size>                      keep at least FLOOR nodes until the deadline
#        (saves an 8-minute start task per batch; FLOOR=0 releases them)
#
# Labels in the output: cand, champ, champ2 (the champion again: the A/A noise floor), ctrl and
# ctrl2 (rivals). wheel: ctrl = C5 (x86) or Rust (arm64), ctrl2 = danielspaangberg's 5760of30030
# wheel (owrb at 1T, epar at all threads). base: ctrl = Rust, ctrl2 = davepl.
# rust: cand/champ are PrimeRust/solution_1 at the two refs, ctrl = our ISPC base at
# CTRL_REF (default origin/hc/champion), ctrl2 = davepl. zig: cand/champ are PrimeZig/solution_4,
# filtered by ZIG_ENTRY (base|wheel), ctrl = our ISPC entry of the same kind at CTRL_REF.
# Cost guards: the deadline in the formula, a wall-clock limit per task, `down` at the end of a
# run. Node-minutes for results/cost-log.csv come from hc-meter.sh, which samples the pools.
set -euo pipefail
: "${SUB:?set SUB to the subscription id}"
BATCH_ACCOUNT="${BATCH_ACCOUNT:-batchllmwestus2gves}"
BATCH_RG="${BATCH_RG:-rg-chris-batch-llm}"
REPO="$(git rev-parse --show-toplevel)"
HERE="$REPO/ispc-dev"
COSTLOG="$HERE/results/cost-log.csv"
azs() { az "$@" --subscription "$SUB"; }
is_arm() { case "$1" in Standard_[A-Z]*[0-9]p*_v*) return 0;; *) return 1;; esac; }
pool_id() { local p="hc-${1,,}"; echo "${p//_/-}"; }

azs batch account login -n "$BATCH_ACCOUNT" -g "$BATCH_RG" --shared-key-auth -o none
SA=$(azs batch account show -n "$BATCH_ACCOUNT" -g "$BATCH_RG" --query autoStorage.storageAccountId -o tsv); SA="${SA##*/}"
SAKEY=$(azs storage account keys list -n "$SA" --query "[0].value" -o tsv)
st() { az storage "$@" --account-name "$SA" --account-key "$SAKEY"; }

# Start task: Docker, the upstream drag-race checkout and the rival images, once per node.
START='set -e
export DEBIAN_FRONTEND=noninteractive DOCKER_BUILDKIT=1
APT="apt-get -o DPkg::Lock::Timeout=600 -qq"
$APT update && $APT install -y docker.io docker-buildx git >/dev/null
cd /root && rm -rf Primes && git clone -q --depth 1 -b drag-race https://github.com/PlummersSoftwareLLC/Primes.git
cd Primes
docker build -q -t rust PrimeRust/solution_1 >/dev/null
docker build -q -t davepl PrimeCPP/solution_5 >/dev/null
if [ "$(uname -m)" = x86_64 ]; then docker build -q -t c5 PrimeC/solution_5 >/dev/null; fi
docker build -q -t dsp PrimeC/solution_2 >/dev/null
touch /root/controls-ready'

# Task script: build cand, champ and (rust/zig kinds) ctx; self-test; warm-up; shuffled rounds.
# SPEC lines: "label|image|docker-run args|grep -E filter".
TASK='set -e
STAGE="$AZ_BATCH_TASK_WORKING_DIR/stage"
export DOCKER_BUILDKIT=1
lscpu | grep -E "Model name|^CPU\(s\)|^Architecture" || true
grep -q avx512f /proc/cpuinfo && echo "AVX-512: yes" || echo "AVX-512: no"
echo "kind=$KIND rounds=$ROUNDS id=$ID"
for d in cand champ ctx; do
  [ -d "$STAGE/$d" ] || continue
  echo "build $d"; docker build -q -t "$d-$ID" "$STAGE/$d" >/dev/null || { echo "!!! build $d failed"; exit 3; }
done
cleanup() { docker rmi -f "cand-$ID" "champ-$ID" "ctx-$ID" >/dev/null 2>&1 || true; }
trap cleanup EXIT
if [ -n "$SELFTEST" ]; then
  for i in cand champ; do
    r=$(docker run --rm -e PRIMES_TEST=1 "$i-$ID" 2>&1; echo "exit=$?")
    echo "self-test $i: $(echo "$r" | grep -c " 1$") ok, $(echo "$r" | grep -c " 0$") bad, $(echo "$r" | tail -1)"
    echo "$r" | tail -1 | grep -q "exit=0" || { echo "!!! self-test $i failed"; exit 4; }
  done
fi
one() {  # $1 round, $2 label; a label may have several spec lines (e.g. 1T and all threads)
  echo "== round $1 $2"
  grep "^$2|" "$STAGE/spec" | while IFS="|" read -r lab img args filt; do
    img=$(echo "$img" | sed "s/@ID/$ID/")
    docker run --rm $img $args 2>/dev/null | grep -E "$filt" || echo "!!! run $2 failed"
  done
}
LABELS=$(cut -d"|" -f1 "$STAGE/spec" | awk "!seen[\$0]++")
for x in $LABELS; do one warmup $x; done
for i in $(seq "$ROUNDS"); do for x in $(echo "$LABELS" | tr " " "\n" | shuf); do one "$i" $x; done; done'

cmd_up() {
  local SIZE=$1 MAXN=${2:-2} MIN=${3:-240} P; P=$(pool_id "$SIZE")
  if az batch pool show --pool-id "$P" -o none 2>/dev/null; then echo "pool $P exists"; return; fi
  local DEADLINE; DEADLINE=$(date -u -d "+$MIN minutes" +%Y-%m-%dT%H:%M:%SZ)
  local SKU=server AGENT="batch.node.ubuntu 24.04"
  is_arm "$SIZE" && { SKU=server-arm64; AGENT="batch.node.ubuntu 24.04-arm64"; }
  local D; D=$(mktemp -d)
  python3 - "$P" "$SIZE" "$SKU" "$AGENT" "$MAXN" "$DEADLINE" "$START" "$D" <<'PY'
import json, sys
pool, size, sku, agent, maxn, deadline, start, d = sys.argv[1:]
formula = ('$q = max(0, $PendingTasks.GetSample(1));\n'
           f'$TargetLowPriorityNodes = time() < time("{deadline}") ? min({maxn}, $q) : 0;\n'
           '$TargetDedicatedNodes = 0;\n$NodeDeallocationOption = taskcompletion;')
json.dump({"id": pool, "vmSize": size, "taskSlotsPerNode": 1,
           "virtualMachineConfiguration": {
               "imageReference": {"publisher": "canonical", "offer": "ubuntu-24_04-lts",
                                  "sku": sku, "version": "latest"},
               "nodeAgentSKUId": agent},
           "startTask": {"commandLine": "/bin/bash -c '" + start.replace("'", "'\\''") + "'",
                         "userIdentity": {"autoUser": {"scope": "pool", "elevationLevel": "admin"}},
                         "waitForSuccess": True, "maxTaskRetryCount": 1},
           "enableAutoScale": True, "autoScaleFormula": formula,
           "autoScaleEvaluationInterval": "PT5M"}, open(f"{d}/pool.json", "w"))
json.dump({"id": pool, "poolInfo": {"poolId": pool}}, open(f"{d}/job.json", "w"))
PY
  az batch pool create --json-file "$D/pool.json" -o none
  az batch job create --json-file "$D/job.json" -o none
  echo "pool $P up (max $MAXN nodes, deadline $DEADLINE)"; rm -rf "$D"
}

kick() {  # set the target to the open task count now; it holds 60 minutes, then the queue metric.
  # The floor (FLOOR env, else the pool's current $floor) keeps nodes warm between batches.
  local P=$1 F N
  F=$(az batch pool show --pool-id "$P" --query autoScaleFormula -o tsv)
  N=$(az batch task list --job-id "$P" --query "[?state!='completed'] | length(@)" -o tsv 2>/dev/null || echo 0)
  F=$(python3 - "$F" "$N" "${FLOOR:-}" <<'PY'
import re, sys, datetime as dt
f, n, floor = sys.argv[1], int(sys.argv[2]), sys.argv[3]
dl = re.findall(r'time\("([^"]+)"\)', f)[-1]
mx = int(re.search(r'min\((\d+),', f).group(1))
fm = re.search(r'\$floor = (\d+);', f)
fl = int(floor) if floor else (int(fm.group(1)) if fm else 0)
hold = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=60)).strftime('%Y-%m-%dT%H:%M:%SZ')
print('$q = max(0, $PendingTasks.GetSample(1));\n'
      f'$hold = time() < time("{hold}") ? min({mx}, {n}) : min({mx}, $q);\n'
      f'$floor = {fl};\n'
      f'$TargetLowPriorityNodes = time() < time("{dl}") ? max($floor, $hold) : 0;\n'
      '$TargetDedicatedNodes = 0;\n$NodeDeallocationOption = taskcompletion;')
PY
)
  # Batch rejects a formula change within 30 s of the last one: retry for up to two minutes.
  for _ in 1 2 3 4; do
    az batch pool autoscale enable --pool-id "$P" --auto-scale-formula "$F" -o none 2>/dev/null && return 0
    sleep 35
  done
  echo "!!! kick failed for $P"
}

ctx_from() {  # $1 ref, $2 path in repo, $3 destination
  mkdir -p "$3"; git -C "$REPO" archive "$1" "$2" | tar -x -C "$3" --strip-components=$(echo "$2" | tr -cd / | wc -c | awk '{print $1+1}')
}

cmd_run() {
  local SIZE=$1 KIND=$2 CAND=$3 CHAMP=$4 OUT=$5 ROUNDS=${6:-5} P; P=$(pool_id "$SIZE")
  local ID; ID="$(date -u +%H%M%S)$RANDOM"; local D; D=$(mktemp -d); local S="$D/stage"; mkdir -p "$S" "$OUT"
  local CTRL_REF="${CTRL_REF:-origin/hc/champion}" SELF=1 X86=1
  is_arm "$SIZE" && X86=
  case "$KIND" in
    wheel) ctx_from "$CAND" PrimeISPC/solution_1 "$S/cand"; ctx_from "$CHAMP" PrimeISPC/solution_1 "$S/champ"
           if [ -n "$X86" ]; then C1='ctrl|c5||^rogiervandam_extend(_epar)?;'
           else C1='ctrl|rust|--bits-extreme|^mike-barber_bit-extreme-hybrid;'; fi
           printf '%s\n' 'cand|cand-@ID||;' 'champ|champ-@ID||;' 'champ2|champ-@ID||;' "$C1" \
             'ctrl2|--entrypoint ./sieve_5760of30030_only_write_read_bits dsp||^danielspaangberg' \
             'ctrl2|--entrypoint ./sieve_5760of30030_epar dsp||^danielspaangberg' > "$S/spec" ;;
    base)  ctx_from "$CAND" PrimeISPC/solution_2 "$S/cand"; ctx_from "$CHAMP" PrimeISPC/solution_2 "$S/champ"
           printf '%s\n' 'cand|cand-@ID||;' 'champ|champ-@ID||;' 'champ2|champ-@ID||;' \
             'ctrl|rust|--bits-extreme|^mike-barber_bit-extreme-hybrid;' \
             'ctrl2|davepl|dummy -l 1000000 -t 1|^davepl' 'ctrl2|davepl|dummy -l 1000000|^davepl' > "$S/spec" ;;
    rust)  SELF=; ctx_from "$CAND" PrimeRust/solution_1 "$S/cand"; ctx_from "$CHAMP" PrimeRust/solution_1 "$S/champ"
           ctx_from "$CTRL_REF" PrimeISPC/solution_2 "$S/ctx"
           printf '%s\n' 'cand|cand-@ID|--bits-extreme|^mike-barber_bit-extreme-hybrid;' \
             'champ|champ-@ID|--bits-extreme|^mike-barber_bit-extreme-hybrid;' \
             'champ2|champ-@ID|--bits-extreme|^mike-barber_bit-extreme-hybrid;' \
             'ctrl|ctx-@ID||;' 'ctrl2|davepl|dummy -l 1000000 -t 1|^davepl' 'ctrl2|davepl|dummy -l 1000000|^davepl' > "$S/spec" ;;
    zig)   local E="${ZIG_ENTRY:-base}" SOL=solution_2; [ "$E" = wheel ] && SOL=solution_1
           ctx_from "$CAND" PrimeZig/solution_4 "$S/cand"; ctx_from "$CHAMP" PrimeZig/solution_4 "$S/champ"
           ctx_from "$CTRL_REF" "PrimeISPC/$SOL" "$S/ctx"
           printf '%s\n' "cand|cand-@ID||^cauldnz-zig-$E;" "champ|champ-@ID||^cauldnz-zig-$E;" \
             "champ2|champ-@ID||^cauldnz-zig-$E;" 'ctrl|ctx-@ID||;' > "$S/spec"
           [ "$E" = base ] && printf '%s\n' 'ctrl2|davepl|dummy -l 1000000 -t 1|^davepl' 'ctrl2|davepl|dummy -l 1000000|^davepl' >> "$S/spec" ;;
    *) echo "unknown kind $KIND" >&2; exit 2 ;;
  esac
  if [ "$KIND" != zig ] && diff -rq "$S/cand" "$S/champ" >/dev/null; then echo "!!! candidate equals champion"; exit 1; fi
  { echo "kind=$KIND cand=$(git -C "$REPO" rev-parse --short "$CAND") champ=$(git -C "$REPO" rev-parse --short "$CHAMP") ctrl_ref=$CTRL_REF"; } > "$OUT/$SIZE.meta"
  printf '%s' "$TASK" > "$S/run.sh"
  tar czf "$D/$ID.tgz" -C "$D" stage
  st container create -n primes-bench -o none
  st blob upload -c primes-bench -n "$ID.tgz" -f "$D/$ID.tgz" --overwrite -o none
  local URL; URL=$(st blob generate-sas -c primes-bench -n "$ID.tgz" --permissions r \
        --expiry "$(date -u -d '+6 hours' +%Y-%m-%dT%H:%MZ)" --https-only --full-uri -o tsv)
  python3 - "$ID" "$URL" "$KIND" "$ROUNDS" "${SELF:+1}" "$D" <<'PY'
import json, sys
tid, url, kind, rounds, selftest, d = sys.argv[1:]
json.dump({"id": tid,
           "commandLine": "/bin/bash -c 'tar xzf stage.tgz && bash stage/run.sh'",
           "resourceFiles": [{"httpUrl": url, "filePath": "stage.tgz"}],
           "environmentSettings": [{"name": "KIND", "value": kind}, {"name": "ROUNDS", "value": rounds},
                                   {"name": "ID", "value": tid}, {"name": "SELFTEST", "value": selftest}],
           "userIdentity": {"autoUser": {"scope": "pool", "elevationLevel": "admin"}},
           "constraints": {"maxWallClockTime": "PT50M", "maxTaskRetryCount": 0}},
          open(f"{d}/task.json", "w"))
PY
  az batch task create --job-id "$P" --json-file "$D/task.json" -o none
  kick "$P"
  echo "### $SIZE $KIND task $ID on $P $(date -u +%T)"
  local SHOWN=0 LAST= T0; T0=$(date +%s)
  while :; do
    local STATE; STATE=$(az batch task show --job-id "$P" --task-id "$ID" --query state -o tsv 2>/dev/null || echo unknown)
    [ "$STATE" != "$LAST" ] && { echo "  $(date -u +%T) task=$STATE"; LAST=$STATE; }
    if [ "$STATE" = running ] || [ "$STATE" = completed ]; then
      rm -f "$D/out.part"
      if az batch task file download --job-id "$P" --task-id "$ID" --file-path stdout.txt \
           --destination "$D/out.part" 2>/dev/null && mv -f "$D/out.part" "$OUT/$SIZE.txt"; then
        local N; N=$(wc -l < "$OUT/$SIZE.txt"); [ "$N" -gt "$SHOWN" ] && tail -n +$((SHOWN + 1)) "$OUT/$SIZE.txt"; SHOWN=$N
      fi
    fi
    [ "$STATE" = completed ] && break
    [ $(( $(date +%s) - T0 )) -gt 4200 ] && { echo "!!! gave up after 70 minutes"; break; }
    sleep 30
  done
  az batch task show --job-id "$P" --task-id "$ID" \
     --query "executionInfo.{exit:exitCode,result:result,start:startTime,end:endTime,failure:failureInfo.message}" -o json 2>/dev/null || true
  local MINS; MINS=$(az batch task show --job-id "$P" --task-id "$ID" --query "[executionInfo.startTime, executionInfo.endTime]" -o tsv 2>/dev/null \
      | python3 -c "import sys,datetime as d;a=sys.stdin.read().split();f=lambda s:d.datetime.fromisoformat(s.replace('Z','+00:00'));print(int((f(a[1])-f(a[0])).total_seconds()//60)+1 if len(a)==2 else 1)")
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$SIZE,$KIND,$ID,$MINS" >> "$HERE/results/hc/tasks.log"   # node cost comes from hc-meter.sh
  st blob delete -c primes-bench -n "$ID.tgz" -o none 2>/dev/null || true
  kick "$P"; rm -rf "$D"
  echo "### done $SIZE $KIND $(date -u +%T)"
}

cmd_down() {
  local P; P=$(pool_id "$1")
  az batch job delete --job-id "$P" --yes 2>/dev/null || true
  az batch pool delete --pool-id "$P" --yes 2>/dev/null || true
  echo "deleting $P"
}

cmd_status() {
  az batch pool list --query "[].{id:id,state:state,alloc:allocationState,nodes:currentLowPriorityNodes,target:targetLowPriorityNodes}" -o table
  for P in $(az batch pool list --query "[].id" -o tsv); do
    echo "$P: $(az batch task list --job-id "$P" --query "[?state!='completed'] | length(@)" -o tsv 2>/dev/null) open tasks"
  done
}

case "${1:-}" in
  floor) shift; kick "$(pool_id "$1")" ;;
  up) shift; cmd_up "$@" ;; run) shift; cmd_run "$@" ;; down) shift; cmd_down "$@" ;;
  status) cmd_status ;; *) sed -n '2,30p' "$0"; exit 2 ;;
esac
