#!/bin/bash
# wait.sh <minutes>: the only way the autopilot waits. Use it for every wait while experiments run,
# in steps of 10 minutes or less.
#
# Every minute it checks ispc-dev/INBOX.md on the remote. If Chris has changed it, it prints the
# new text and returns at once with exit code 10: read the message and act on it before
# anything else.
# Every 5 minutes (and before returning) it runs the heartbeat:
#   - starts hc-meter.sh if Azure pools exist and the meter isn't running;
#   - refreshes spend from results/cost-log.csv;
#   - updates status.json (updated_utc and the background-run count) and publishes the page.
# It also prints the last line of each background run log, so the waiting session sees progress.
# Exit codes: 0 waited the full time; 10 new message in INBOX.md.
# WAIT_DRYRUN=1 checks the inbox but skips the heartbeat's writes and pushes (for testing).
set -uo pipefail
MIN=${1:-10}; [ "$MIN" -gt 10 ] && MIN=10
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$ROOT/ispc-dev/tools"
SEEN=/tmp/hc-inbox.seen
LOGDIR=${LOGDIR:-/tmp/hc-logs}

inbox_check() {
    git -C "$ROOT" fetch -q origin ispc-dev 2>/dev/null || return 1
    local body hash
    body="$(git -C "$ROOT" show origin/ispc-dev:ispc-dev/INBOX.md 2>/dev/null)" || return 1
    hash="$(printf '%s' "$body" | sha1sum | cut -c1-12)"
    if [ ! -f "$SEEN" ]; then echo "$hash" > "$SEEN"; return 1; fi   # first call: baseline only
    [ "$hash" = "$(cat "$SEEN")" ] && return 1
    echo "$hash" > "$SEEN"
    echo "================ NEW MESSAGE FROM CHRIS (INBOX.md, $hash) ================"
    printf '%s\n' "$body"
    echo "=========================================================================="
    echo "Act on it now (AUTOPILOT.md, 'Messages from Chris'), then record it with:"
    echo "  python3 ispc-dev/tools/st.py set run.inbox_ack '\"$hash $(date -u +%H:%MZ)\"'"
    return 0
}

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
    if inbox_check; then heartbeat; exit 10; fi
    if (( m % 5 == 0 )); then heartbeat; fi
done
(( MIN % 5 == 0 )) || heartbeat
exit 0
