#!/bin/bash
# prun.sh <tag> <size> <kind> <cand-ref> <champ-ref> <outdir> [rounds]
# Runs one hc-pool.sh task in the background; log in $LOGDIR/<tag>-<size>.log (default /tmp/hc-logs).
# Copy hc-pool.sh first so a git checkout during the run can't change the script under it.
TAG=$1; shift
LOGDIR=${LOGDIR:-/tmp/hc-logs}; mkdir -p "$LOGDIR"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cp "$ROOT/ispc-dev/hc-pool.sh" "$LOGDIR/hc-pool-copy.sh"
cd "$ROOT" && SUB=$AZURE_SUBSCRIPTION_ID setsid nohup bash "$LOGDIR/hc-pool-copy.sh" run "$@" > "$LOGDIR/$TAG-$1.log" 2>&1 &
