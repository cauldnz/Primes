#!/bin/bash
# pub.sh "message": commit ispc-dev notes and status.json, push ispc-dev, publish the dashboard.
# Set TRAILER to the session's commit attribution lines (they end every commit message).
cd "$(dirname "$0")/../.."
# The log writes itself: every change to experiments, phase, scoreboard or run state becomes an
# event, here and in results/hc/EVENTS.jsonl. The climber can still add its own with st.py event.
python3 ispc-dev/tools/autolog.py diff || echo "pub: autolog failed; publishing anyway"
git add ispc-dev
git commit -qm "${1:-Status update}

${TRAILER}" || true
for i in 1 2 3; do git pull -q --rebase --autostash origin ispc-dev && git push -q origin ispc-dev && break; sleep $((2**i)); done
bash ispc-dev/dashboard/publish.sh 2>&1 | tail -1
