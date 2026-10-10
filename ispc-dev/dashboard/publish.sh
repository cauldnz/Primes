#!/usr/bin/env bash
# Rebuild the status page from the machine's status.json and push it to the `dashboard` branch,
# which GitHub Pages can serve (Settings, Pages, branch `dashboard`, folder /).
# Run from anywhere inside the repo, after committing status.json.
#
# The branch holds only the page files (index.html, log.html, .nojekyll). It is built with git
# plumbing from a temporary folder, so it never picks up the rest of the repo and needs no
# worktree or local branch.
set -euo pipefail
HC="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(git -C "$HC" rev-parse --show-toplevel)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/site"
python3 "$HC/dashboard/build.py" "$HC/status.json" "$TMP/site/index.html" >/dev/null
touch "$TMP/site/.nojekyll"

cd "$REPO"
PARENT=""
if git fetch -q origin dashboard 2>/dev/null; then PARENT=$(git rev-parse -q --verify FETCH_HEAD || true); fi
export GIT_INDEX_FILE="$TMP/index"
git --work-tree="$TMP/site" add -A .
TREE=$(git write-tree)
unset GIT_INDEX_FILE
if [ -n "$PARENT" ] && [ "$(git rev-parse "$PARENT^{tree}")" = "$TREE" ]; then
    echo "page unchanged"; exit 0
fi
COMMIT=$(git commit-tree "$TREE" ${PARENT:+-p "$PARENT"} -m "Status page $(date -u +%Y-%m-%dT%H:%MZ)")
git push -q origin "$COMMIT:refs/heads/dashboard"
echo "published to the dashboard branch"
