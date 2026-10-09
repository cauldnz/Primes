#!/bin/bash
# prun.sh <tag> <size> <kind> <cand-ref> <champ-ref> <outdir> [rounds]
# Runs one hc-pool.sh task in the background; log in $LOGDIR/<tag>-<size>.log (default /tmp/hc-logs).
# Copies hc-pool.sh first so a git checkout during the run can't change the script under it.
TAG=$1; shift
LOGDIR=${LOGDIR:-/tmp/hc-logs}; mkdir -p "$LOGDIR"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# One copy per run: bash reads a script as it executes it, so overwriting a shared copy while
# other runs use it can kill them (it did, 2026-10-10).
COPY="$LOGDIR/hc-pool-$TAG-$1-$$.sh"
cp "$ROOT/ispc-dev/hc-pool.sh" "$COPY"
cd "$ROOT" && SUB=$AZURE_SUBSCRIPTION_ID setsid nohup bash "$COPY" run "$@" > "$LOGDIR/$TAG-$1.log" 2>&1 &
