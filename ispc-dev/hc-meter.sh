#!/usr/bin/env bash
# Sample the hc-* pools once a minute; every 5 minutes append node-minutes per size to results/cost-log.csv,
# so persistent pools are costed like the old one-pool-per-run mode (date,mode,size,minutes).
# Usage: hc-meter.sh [stop-file]   Runs until stop-file exists (default /tmp/hc-meter.stop).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; STOP="${1:-/tmp/hc-meter.stop}"
declare -A ACC
flush() {
  for k in "${!ACC[@]}"; do [ "${ACC[$k]}" -gt 0 ] && echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),batch-pool,$k,${ACC[$k]}" >> "$HERE/results/cost-log.csv"; ACC[$k]=0; done
}
trap flush EXIT
N=0
while [ ! -f "$STOP" ]; do
  while read -r size nodes; do
    [ -z "$size" ] && continue; size=$(echo "$size" | sed 's/^standard_/Standard_/; s/_\([a-z0-9]*\)$/_\1/')
    ACC[$size]=$(( ${ACC[$size]:-0} + nodes ))
  done < <(az batch pool list --query "[?starts_with(id,'hc-')].[vmSize, currentLowPriorityNodes]" -o tsv 2>/dev/null)
  N=$((N + 1)); [ $((N % 5)) -eq 0 ] && flush
  sleep 60
done
