#!/usr/bin/env python3
"""Summarise SUITE=ab logs from azure-epyc-bench.sh and apply the HILL-CLIMB.md acceptance rule.

Usage: python ispc-dev/analyze.py results/hc/<id>/*.txt

Each log is one machine. Rounds are "== round <n> <label>" followed by result lines
"label;passes;seconds;threads;tags". Labels: cand, champ, champ2 (the champion again, for the
A/A noise floor), ctrl (C5 or mike-barber Rust) and, from hc-pool.sh runs, ctrl2 (davepl C++).
The warm-up round is ignored.

Per machine and thread count it prints medians and ranges, the same-round ratio cand/champ (median
and range, then mean, 95% confidence interval and SD of the per-round ratios), the A/A spread
champ2/champ, cand/ctrl and cand/ctrl2. The interval is reported, not yet used in the verdict. Then it gives a verdict (HILL-CLIMB.md, "Acceptance rule", from 2026-10-10), on the mean of the
per-round ratio and its 95% confidence interval, at 1 thread or all threads, whichever is better:
  KEEP         the interval's lower end is at least +1% on both Zen 3 and Zen 5, and nothing
               loses 1% or more on the mean.
  MORE ROUNDS  the interval straddles +1%; it estimates how many rounds would settle it.
  REVERT       a regression of 1% or more anywhere, an interval that can't reach +1%, or 20
               rounds without settling.
A/A intervals that exclude zero by more than 0.5% mark the machine NOISY: rerun it elsewhere.
HILL-CLIMB.md requires Zen 3 and Zen 5 logs for a decision; the script warns if either is missing.
"""
import re
import statistics
import sys
from collections import defaultdict


def parse(path):
    machine, rounds = "?", defaultdict(lambda: defaultdict(dict))
    rnd = label = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            m = re.match(r"Model name:\s+(.*)", line)
            if m and machine == "?":
                machine = m.group(1).strip()
            m = re.match(r"== round (\S+) (\S+)$", line)
            if m:
                rnd, label = m.group(1), m.group(2)
                continue
            parts = line.split(";")
            if rnd and rnd != "warmup" and len(parts) == 5 and parts[1].isdigit():
                rounds[rnd][label][int(parts[3])] = int(parts[1])
                RATES[path][label][int(parts[3])].append(int(parts[1]) / float(parts[2]) / int(parts[3]))
    return machine, rounds


# two-sided 95% t critical values by degrees of freedom (n - 1)
T95 = {1: 12.71, 2: 4.30, 3: 3.18, 4: 2.78, 5: 2.57, 6: 2.45, 7: 2.36, 8: 2.31, 9: 2.26,
       10: 2.23, 11: 2.20, 12: 2.18, 13: 2.16, 14: 2.14, 15: 2.13, 19: 2.09, 24: 2.06, 29: 2.05}


THRESH = 0.01      # keep when the 95% interval's lower end clears +1% on both deciding machines
REGRESS = 0.01     # revert when any machine or thread count loses 1% or more on the mean
MAX_ROUNDS = 20    # stop adding rounds here


# passes per second per thread, per file, label and thread count: the official multi-thread
# table ranks by this (upstream tools/src/formatters/table.ts).
RATES = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
LABELS = ("cand", "champ", "champ2", "ctrl", "ctrl2", "ctrl3")


def per_thread_table(path):
    r = RATES.get(path)
    if not r:
        return
    labs = [l for l in LABELS if l in r and l != "champ2"]
    ts = sorted({t for l in labs for t in r[l]})
    print("\nPer thread (passes / s / thread, median over counted rounds; the leaderboard's multi-thread sort key):\n")
    print("| threads | " + " | ".join(labs) + " |")
    print("|---|" + "---|" * len(labs))
    for t in ts:
        print(f"| {t} | " + " | ".join(f"{statistics.median(r[l][t]):.0f}" if r[l].get(t) else "-" for l in labs) + " |")


def ci95(xs):
    """Mean, SD and 95% confidence half-width of the paired per-round ratios."""
    n = len(xs)
    if n < 2:
        return (xs[0] if xs else 1.0), 0.0, float("nan")
    m, sd = statistics.mean(xs), statistics.stdev(xs)
    t = T95.get(n - 1) or T95[max(k for k in T95 if k <= n - 1)]
    return m, sd, t * sd / n ** 0.5


def pct(x):
    return f"{(x - 1) * 100:+.1f}%"


def kfmt(v):
    return f"{v / 1e6:.2f}M" if v >= 1e6 else f"{v / 1e3:.1f}k"


def summarise(path):
    machine, rounds = parse(path)
    threads = sorted({t for r in rounds.values() for lab in r.values() for t in lab})
    out = {"machine": machine, "file": path, "rounds": len(rounds), "metrics": {}}
    for t in threads:
        series = defaultdict(list)
        ratios = defaultdict(list)
        for r in rounds.values():
            v = {lab: r[lab].get(t) for lab in LABELS}
            for lab, x in v.items():
                if x:
                    series[lab].append(x)
            if v["cand"] and v["champ"]:
                ratios["cand/champ"].append(v["cand"] / v["champ"])
            if v["champ2"] and v["champ"]:
                ratios["aa"].append(v["champ2"] / v["champ"])
            if v["cand"] and v["ctrl"]:
                ratios["cand/ctrl"].append(v["cand"] / v["ctrl"])
            if v["cand"] and v["ctrl2"]:
                ratios["cand/ctrl2"].append(v["cand"] / v["ctrl2"])
            if v["cand"] and v["ctrl3"]:
                ratios["cand/ctrl3"].append(v["cand"] / v["ctrl3"])
        out["metrics"][t] = (series, ratios)
    return out


def main(paths):
    if not paths:
        sys.exit(__doc__)
    results = [summarise(p) for p in paths]
    deciding = {}          # machine -> best (lower bound, mean, sd, n) at 1T or all threads
    worst = (1.0, "")      # lowest mean ratio anywhere, and where
    noisy = []
    for res in results:
        print(f"\n### {res['machine']}  ({res['rounds']} scored rounds, {res['file']})\n")
        print("| threads | cand | champ | champ2 | ctrl | ctrl2 | cand/champ median (range) | mean ± 95% CI (SD) | rounds won | A/A spread | cand/ctrl | cand/ctrl2 | ctrl3 | cand/ctrl3 |")
        print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        tmax = max(res["metrics"]) if res["metrics"] else 1
        for t, (series, ratios) in sorted(res["metrics"].items()):
            med = {lab: statistics.median(s) for lab, s in series.items() if s}
            cc = ratios["cand/champ"]
            if not cc:
                continue
            gain = statistics.median(cc)
            won = sum(1 for x in cc if x > 1)
            mu, sd, hw = ci95(cc)
            ci_txt = f"{pct(mu)} ± {hw * 100:.1f}% ({sd * 100:.1f}%)" if hw == hw else "n/a"
            aa = ratios["aa"]
            aa_txt = f"{min(aa) - 1:+.1%} to {max(aa) - 1:+.1%}" if aa else "n/a"
            if len(aa) > 1:
                amu, _, ahw = ci95(aa)
                if abs(amu - 1) - ahw > 0.005:      # the champion against itself differs: a noisy node
                    noisy.append(f"{res['machine']} {t}T (A/A {pct(amu)} ± {ahw * 100:.1f}%)")
            ctrl = pct(statistics.median(ratios["cand/ctrl"])) if ratios["cand/ctrl"] else "n/a"
            ctrl2 = pct(statistics.median(ratios["cand/ctrl2"])) if ratios["cand/ctrl2"] else "n/a"
            print(f"| {t} | " + " | ".join(kfmt(med[l]) if l in med else "-" for l in ("cand", "champ", "champ2", "ctrl", "ctrl2"))
                  + f" | {pct(gain)} ({pct(min(cc))} to {pct(max(cc))}) | {ci_txt} | {won}/{len(cc)} | {aa_txt} | {ctrl} | {ctrl2} | "
                  + (kfmt(med["ctrl3"]) if "ctrl3" in med else "-") + " | "
                  + (pct(statistics.median(ratios["cand/ctrl3"])) if ratios["cand/ctrl3"] else "n/a") + " |")
            if mu < worst[0]:
                worst = (mu, f"{res['machine']} {t}T")
            if t in (1, tmax) and hw == hw:
                cand = (mu - hw, mu, sd, len(cc))
                key = res["machine"]
                if key not in deciding or cand[0] > deciding[key][0]:
                    deciding[key] = cand
        per_thread_table(res["file"])

    names = " ".join(r["machine"] for r in results)
    need = {"Zen 3": "7763|7V73|Zen 3", "Zen 5": "9V45|9005|Zen 5"}
    picked = {}
    for label, pat in need.items():
        hits = [v for m, v in deciding.items() if re.search(pat, m)]
        if hits:
            picked[label] = max(hits)
        else:
            print(f"\nWARNING: no {label} log; HILL-CLIMB.md needs Zen 3 and Zen 5 for a decision.")
    if noisy:
        print("\nNOISY: the champion differs from itself beyond 0.5% on " + "; ".join(noisy)
              + ". Treat this machine's result as inconclusive and rerun it, ideally on another node.")
    if not picked:
        print("\nVERDICT: NO DATA")
        return
    lows = [v[0] for v in picked.values()]
    if worst[0] <= 1 - REGRESS:
        verdict = f"REVERT (regresses {pct(worst[0])} on {worst[1]})"
    elif len(picked) == 2 and min(lows) >= 1 + THRESH:
        verdict = "KEEP (95% interval clears +1% on both Zen machines)"
    elif any(v[1] + (v[1] - v[0]) < 1 + THRESH for v in picked.values()) or max(v[3] for v in picked.values()) >= MAX_ROUNDS:
        verdict = "REVERT (the interval can't reach +1% on both machines, or the round limit is reached)"
    else:
        est = []
        for label, (lo, mu, sd, n) in picked.items():
            if lo < 1 + THRESH and mu > 1 + THRESH and sd > 0:
                k = (2.1 * sd / (mu - 1 - THRESH)) ** 2
                est.append(f"{label} about {min(MAX_ROUNDS, max(n + 2, int(k + 0.999)))}")
        more = "; ".join(est) if est else f"up to {MAX_ROUNDS}"
        verdict = f"MORE ROUNDS (the interval straddles +1%; rounds needed: {more})"
    print(f"\nVERDICT: {verdict}")


if __name__ == "__main__":
    main(sys.argv[1:])
