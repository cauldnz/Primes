#!/usr/bin/env python3
"""Summarise SUITE=ab logs from azure-epyc-bench.sh and apply the HILL-CLIMB.md acceptance rule.

Usage: python ispc-dev/analyze.py results/hc/<id>/*.txt

Each log is one machine. Rounds are "== round <n> <label>" followed by result lines
"label;passes;seconds;threads;tags". Labels: cand, champ, champ2 (the champion again, for the
A/A noise floor), ctrl (C5 or mike-barber Rust) and, from hc-pool.sh runs, ctrl2 (davepl C++).
The warm-up round is ignored.

Per machine and thread count it prints medians and ranges, the same-round ratio cand/champ, the
A/A spread champ2/champ, cand/ctrl and cand/ctrl2. Then it gives a verdict:
  KEEP    median gain >= 2% at 1T or all-threads on every machine; on at least one machine the
          candidate beat the champion in every round on that metric; nothing regresses > 1%.
  RERUN   no regression > 1% and the best gain is between 0% and 2% (rerun with 10 rounds).
  REVERT  anything else.
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
    return machine, rounds


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
            v = {lab: r[lab].get(t) for lab in ("cand", "champ", "champ2", "ctrl", "ctrl2")}
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
        out["metrics"][t] = (series, ratios)
    return out


def main(paths):
    if not paths:
        sys.exit(__doc__)
    results = [summarise(p) for p in paths]
    decisive = []          # per machine: (best median gain at 1T/all-threads, every-round win?)
    worst = 1.0
    for res in results:
        print(f"\n### {res['machine']}  ({res['rounds']} scored rounds, {res['file']})\n")
        print("| threads | cand | champ | champ2 | ctrl | ctrl2 | cand/champ median (range) | rounds won | A/A spread | cand/ctrl | cand/ctrl2 |")
        print("|---|---|---|---|---|---|---|---|---|")
        tmax = max(res["metrics"]) if res["metrics"] else 1
        best = None
        for t, (series, ratios) in sorted(res["metrics"].items()):
            med = {lab: statistics.median(s) for lab, s in series.items() if s}
            cc = ratios["cand/champ"]
            if not cc:
                continue
            gain = statistics.median(cc)
            won = sum(1 for x in cc if x > 1)
            aa = ratios["aa"]
            aa_txt = f"{min(aa) - 1:+.1%} to {max(aa) - 1:+.1%}" if aa else "n/a"
            ctrl = pct(statistics.median(ratios["cand/ctrl"])) if ratios["cand/ctrl"] else "n/a"
            ctrl2 = pct(statistics.median(ratios["cand/ctrl2"])) if ratios["cand/ctrl2"] else "n/a"
            print(f"| {t} | " + " | ".join(kfmt(med[l]) if l in med else "-" for l in ("cand", "champ", "champ2", "ctrl", "ctrl2"))
                  + f" | {pct(gain)} ({pct(min(cc))} to {pct(max(cc))}) | {won}/{len(cc)} | {aa_txt} | {ctrl} | {ctrl2} |")
            worst = min(worst, gain)
            if t in (1, tmax):
                cand = (gain, won == len(cc))
                best = cand if best is None or cand[0] > best[0] else best
        if best:
            decisive.append(best)

    names = " ".join(r["machine"] for r in results)
    for need, pat in (("Zen 3", "7763|7V73|Zen 3"), ("Zen 5", "9V45|9005|Zen 5")):
        if not re.search(pat, names):
            print(f"\nWARNING: no {need} log; HILL-CLIMB.md needs Zen 3 and Zen 5 for a decision.")
    if not decisive:
        print("\nVERDICT: NO DATA")
        return
    all_gain = all(g >= 1.02 for g, _ in decisive)
    any_clean = any(w for _, w in decisive)
    if worst < 0.99:
        verdict = f"REVERT (a machine/thread count regresses {pct(worst)})"
    elif all_gain and any_clean:
        verdict = "KEEP"
    elif max(g for g, _ in decisive) > 1.0:
        verdict = "RERUN with 10 rounds (gain under 2%, or not clean in every round)"
    else:
        verdict = "REVERT (no gain)"
    print(f"\nVERDICT: {verdict}")


if __name__ == "__main__":
    main(sys.argv[1:])
