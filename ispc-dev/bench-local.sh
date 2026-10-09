#!/usr/bin/env bash
# Interleaved A/B benchmark on the local machine (the cloud container when run by the autopilot).
#
# Usage: ispc-dev/bench-local.sh <solution_1|solution_2> <champion-ref> <candidate-ref> [rounds]
#   Builds PrimeISPC/<solution> at both git refs with the distro ispc, builds the control entry
#   (rogiervandam C for solution_1, mike-barber Rust for solution_2), runs `rounds` interleaved
#   rounds (default 7), discards round 1 as warm-up, and prints medians. Raw output goes to
#   ispc-dev/results/hc/local-<timestamp>/.
# Requires: ispc and gcc (apt), cargo for the Rust control, make for the C control.
set -euo pipefail

SOL="$1"; CHAMP="$2"; CAND="$3"; ROUNDS="${4:-7}"
REPO="$(git rev-parse --show-toplevel)"
WORK="$(mktemp -d)"
OUT="$REPO/ispc-dev/results/hc/local-$(date -u +%Y%m%dT%H%MZ)"
mkdir -p "$OUT"
SRC=primes.ispc; [ "$SOL" = solution_2 ] && SRC=primes_base.ispc

build_ref() {  # $1 = label, $2 = git ref
    local d="$WORK/$1"; mkdir -p "$d"
    for f in "$SRC" build.sh; do git -C "$REPO" show "$2:PrimeISPC/$SOL/$f" > "$d/$f"; done
    (cd "$d" && ISPC="${ISPC:-ispc}" sh build.sh >/dev/null)
    (cd "$d" && PRIMES_TEST=1 ./primes >/dev/null) || { echo "self-test failed for $1 ($2)" >&2; exit 1; }
}
build_ref champion "$CHAMP"
build_ref candidate "$CAND"

if [ "$SOL" = solution_1 ]; then
    CTRL_NAME=rogiervandam_c5
    cp -r "$REPO/PrimeC/solution_5" "$WORK/c5"
    (cd "$WORK/c5" && ./sieve compileall >/dev/null 2>&1)
    CTRL_CMD="$WORK/c5/bin/sieve_extend"
    CTRL_MT="$WORK/c5/bin/sieve_extend_epar"
else
    CTRL_NAME=mikebarber_rust
    cp -r "$REPO/PrimeRust/solution_1" "$WORK/rust"
    (cd "$WORK/rust" && RUSTFLAGS="-C target-cpu=native" cargo build --release -q 2>/dev/null)
    CTRL_CMD="$WORK/rust/target/release/prime-sieve-rust"
    CTRL_MT=""
fi

{ echo "solution=$SOL champion=$CHAMP candidate=$CAND rounds=$ROUNDS"; lscpu | grep 'Model name'; } > "$OUT/meta.txt"
for r in $(seq 1 "$ROUNDS"); do
    echo "== round $r champion"  >> "$OUT/raw.txt"; "$WORK/champion/primes"  >> "$OUT/raw.txt"
    echo "== round $r candidate" >> "$OUT/raw.txt"; "$WORK/candidate/primes" >> "$OUT/raw.txt"
    echo "== round $r control"   >> "$OUT/raw.txt"
    if [ "$SOL" = solution_1 ]; then
        "$CTRL_CMD" 2>/dev/null | tail -1 >> "$OUT/raw.txt"
        OMP_NUM_THREADS="$(nproc)" "$CTRL_MT" 2>/dev/null | tail -1 >> "$OUT/raw.txt"
    else
        "$CTRL_CMD" -t 1 2>/dev/null | grep 'extreme-hybrid' >> "$OUT/raw.txt" || true
        "$CTRL_CMD" -t "$(nproc)" 2>/dev/null | grep 'extreme-hybrid' >> "$OUT/raw.txt" || true
    fi
done

python3 - "$OUT/raw.txt" "$CTRL_NAME" <<'EOF' | tee "$OUT/summary.txt"
import sys, re, statistics as st, collections
raw, ctrl = sys.argv[1], sys.argv[2]
d = collections.defaultdict(list); rnd = 0; who = None
for ln in open(raw):
    m = re.match(r'== round (\d+) (\w+)', ln)
    if m: rnd, who = int(m.group(1)), m.group(2); continue
    p = ln.strip().split(';')
    if len(p) >= 4 and p[1].isdigit() and rnd > 1:          # round 1 is warm-up
        d[(who, int(p[3]))].append(int(p[1]))
for th in sorted({k[1] for k in d}):
    c, n = d.get(('champion', th)), d.get(('candidate', th))
    if not c or not n: continue
    wins = sum(1 for a, b in zip(c, n) if b > a)
    delta = (st.median(n) / st.median(c) - 1) * 100
    k = d.get(('control', th))
    ctl = f"  {ctrl} {st.median(k):,.0f}" if k else ""
    print(f"{th:>3}T  champion {st.median(c):>9,.0f}  candidate {st.median(n):>9,.0f}  "
          f"delta {delta:+.1f}%  candidate won {wins}/{len(n)} rounds{ctl}")
EOF
rm -rf "$WORK"
echo "raw results: $OUT"
