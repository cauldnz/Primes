#!/usr/bin/env bash
# Rebuild the status page from ispc-dev/status.json and push it to the `dashboard` branch,
# which GitHub Pages serves at https://cauldnz.github.io/Primes/.
# Run from anywhere inside the repo, after committing status.json on ispc-dev.
set -euo pipefail
REPO="$(git rev-parse --show-toplevel)"
TMP="$(mktemp -d)"
python3 "$REPO/ispc-dev/dashboard/build.py" "$REPO/ispc-dev/status.json" "$TMP/index.html" >/dev/null
touch "$TMP/.nojekyll"
WT="$(mktemp -d)"
if git -C "$REPO" ls-remote --exit-code --heads origin dashboard >/dev/null 2>&1; then
    git -C "$REPO" fetch -q origin dashboard:refs/remotes/origin/dashboard
    git -C "$REPO" worktree add -q -B dashboard "$WT" origin/dashboard
else
    git -C "$REPO" worktree add -q --detach "$WT"
    git -C "$WT" checkout -q --orphan dashboard
    git -C "$WT" rm -rq . >/dev/null 2>&1 || true
fi
cp "$TMP/index.html" "$TMP/.nojekyll" "$WT/"
[ -f "$TMP/log.html" ] && cp "$TMP/log.html" "$WT/"
git -C "$WT" add index.html .nojekyll $( [ -f "$TMP/log.html" ] && echo log.html )
git -C "$WT" commit -qm "Status page $(date -u +%Y-%m-%dT%H:%MZ)" || true
git -C "$WT" push -q origin dashboard
git -C "$REPO" worktree remove --force "$WT"
rm -rf "$TMP"
echo "published: https://cauldnz.github.io/Primes/"
