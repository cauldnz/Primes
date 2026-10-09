#!/bin/bash
# pub.sh "message": commit ispc-dev notes and status.json, push ispc-dev, publish the dashboard.
# Set TRAILER to the session's commit attribution lines (they end every commit message).
cd "$(dirname "$0")/../.."
git add ispc-dev
git commit -qm "${1:-Status update}

${TRAILER}" || true
for i in 1 2 3; do git pull -q --rebase --autostash origin ispc-dev && git push -q origin ispc-dev && break; sleep $((2**i)); done
bash ispc-dev/dashboard/publish.sh 2>&1 | tail -1
