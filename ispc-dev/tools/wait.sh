#!/bin/bash
# wait.sh <minutes>: the only way the autopilot waits. Use it for every wait while experiments run,
# in steps of 10 minutes or less.
#
# Every 5 minutes (and before returning) it runs the heartbeat:
#   - starts hc-meter.sh if Azure pools exist and the meter isn't running;
#   - refreshes spend from results/cost-log.csv;
#   - updates status.json (updated_utc and the background-run count) and publishes the page.
# It also prints the last line of each background run log, so the waiting session sees progress.
# WAIT_DRYRUN=1 skips the heartbeat's writes and pushes (for testing).
# Steering never comes through files: Chris messages the session directly (AUTOPILOT.md).
set -uo pipefail
MIN=${1:-10}; [ "$MIN" -gt 10 ] && MIN=10
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$ROOT/ispc-dev/tools"
LOGDIR=${LOGDIR:-/tmp/hc-logs}

heartbeat() {
    if [ -n "${WAIT_DRYRUN:-}" ]; then echo "heartbeat (dry run): would refresh spend and publish"; return; fi
    if command -v az >/dev/null 2>&1 && ! pgrep -f hc-meter.sh >/dev/null 2>&1; then
        if [ -n "$(az batch pool list --query "[?starts_with(id,'hc-')].id" -o tsv 2>/dev/null)" ]; then
            setsid nohup bash "$ROOT/ispc-dev/hc-meter.sh" > /tmp/hc-meter.log 2>&1 &
            python3 "$T/st.py" event "Cost meter was not running; started it." warn >/dev/null
        fi
    fi
    python3 "$T/st.py" spend >/dev/null 2>&1 || true
    local n; n=$(pgrep -fc hc-pool-copy.sh 2>/dev/null || echo 0)
    python3 "$T/st.py" set run.background_runs "$n" >/dev/null
    bash "$T/pub.sh" "Heartbeat" >/dev/null 2>&1 || echo "heartbeat: publish failed (will retry)"
    for f in "$LOGDIR"/*.log; do [ -f "$f" ] && printf '%s: %s\n' "$(basename "$f")" "$(tail -n1 "$f" | cut -c1-160)"; done
}

for ((m = 1; m <= MIN; m++)); do
    sleep 60
    if (( m % 5 == 0 )); then heartbeat; fi
done
(( MIN % 5 == 0 )) || heartbeat
exit 0
