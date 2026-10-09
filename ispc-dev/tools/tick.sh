#!/bin/bash
# tick.sh: run this first in every tick of a /loop climb (AUTOPILOT.md, "The tick").
#   1. collects results: partial output of running Batch tasks, final output of finished ones;
#   2. tallies Azure node-minutes since the last tick and refreshes spend in status.json;
#   3. publishes the status page (commit, push, Pages) with a heartbeat;
#   4. prints what the climber needs to decide: open jobs, newly finished outputs, spend, time left.
# It never decides anything: deciding, submitting and scheduling the next wake-up are the
# climber's job. Safe to run on a fresh machine: all state comes from git and Azure Batch.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$ROOT/ispc-dev/tools"
cd "$ROOT"
git pull -q --rebase --autostash origin ispc-dev 2>/dev/null || echo "tick: pull failed; working from the local copy"

echo "== collect"
SUB=${AZURE_SUBSCRIPTION_ID:-} bash ispc-dev/hc-pool.sh collect 2>&1 | tail -n 30
echo "== cost"
SUB=${AZURE_SUBSCRIPTION_ID:-} bash ispc-dev/hc-pool.sh tally 2>&1 | tail -n 3
SPEND=$(python3 "$T/st.py" spend 2>/dev/null || echo "?")
echo "spend this run: NZ\$$SPEND (stop new pools at NZ\$25)"

python3 - <<'PY'
import json, datetime, os
s = json.load(open("ispc-dev/status.json")); r = s.get("run", {})
try:
    start = datetime.datetime.fromisoformat(r["started_utc"].replace("Z", "+00:00"))
    used = (datetime.datetime.now(datetime.timezone.utc) - start).total_seconds() / 3600
    print(f"time used: {used:.2f} h of {r.get('time_box_hours', 4)} h")
except Exception:
    print("time used: unknown (run.started_utc not set)")
PY

OPEN=$(awk -F'\t' 'NR > 1 && $7 == "open"' ispc-dev/results/hc/jobs.tsv 2>/dev/null | wc -l)
python3 "$T/st.py" set run.background_runs "$OPEN" >/dev/null
python3 "$T/st.py" set run.last_tick_utc "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" >/dev/null
bash "$T/pub.sh" "Tick" >/dev/null 2>&1 || echo "tick: publish failed; retry with tools/pub.sh"
echo "== open jobs: $OPEN"
awk -F'\t' 'NR > 1 && $7 == "open" { print "  " $1, $3, $4, "->", $5 }' ispc-dev/results/hc/jobs.tsv 2>/dev/null
echo "Next: analyse finished outputs (analyze.py), decide, submit (hc-pool.sh submit), log, publish,"
echo "then schedule the next wake-up and end the turn."
