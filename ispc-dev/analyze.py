#!/usr/bin/env python3
"""Summarise SUITE=ab logs from azure-epyc-bench.sh and apply the HILL-CLIMB.md acceptance rule.

Usage: python ispc-dev/analyze.py results/hc/<id>/*.txt

Each log is one machine. Rounds are "== round <n> <label>" followed by result lines
"label;passes;seconds;threads;tags". Labels: cand, champ, champ2 (the champion again, for the
A/A noise floor), ctrl (C5 or mike-barber Rust) and, from hc-pool.sh runs, ctrl2 (davepl C++).
The warm-up round is ignored.

Per machine and thread count it prints medians and ranges, the same-round ratio cand/champ (median
and range, then mean, 95% confidence interval and SD of the per-round ratios), the A/A spread
champ2/champ, cand/ctrl and cand/ctrl2. The interval is reported, not yet used in the verdict. Then it gives a verdict (HILL-CLIMB.md, "Acceptance rule", per thread, from 2026-10-11), on the
mean of the per-round ratio and its 95% confidence interval at 1 thread and at 4 threads:
  KEEP         the lower end is at least +1% at 1T or 4T on both Zen 3 and Zen 5, and neither
               1T nor 4T loses 1% or more on Zen 3, Zen 5, Intel AVX2 or Cobalt (the gates).
  (all-threads is recorded, not decided: a loss over 5% there is printed for Chris)
  MORE ROUNDS  the interval straddles +1%; it estimates how many rounds would settle it.
  REVERT       a regression of 1% or more anywhere, an interval that can't reach +1%, or 20
               rounds without settling.
A/A intervals that exclude zero by more than 0.5% mark the machine NOISY: rerun it elsewhere.
HILL-CLIMB.md requires Zen 3 and Zen 5 logs for a decision; the script warns if either is missing.
"""
import os, re
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
    stats = {}             # (file, threads) -> (lower bound, mean, sd, n, is all-threads)
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
            if hw == hw:
                stats[(res["file"], t)] = (mu - hw, mu, sd, len(cc), t == tmax)
        per_thread_table(res["file"])

    verdict(results, stats, noisy)


# Which chip each Azure size should give (HILL-CLIMB.md: a log on the wrong chip doesn't count).
SIZE_CHIP = {"Standard_D16a_v4": "7763", "Standard_D16as_v7": "9V45", "Standard_D32as_v7": "9V45",
             "Standard_D96as_v7": "9V45", "Standard_D16as_v6": "9V74", "Standard_D16as_v5": "9V74",
             "Standard_D16s_v5": "Xeon", "Standard_D4ps_v6": "Neoverse|N2|Cobalt|ARM|aarch64"}
ROLE = [("Zen 5", "9V45|9005|Zen 5", "decide"), ("Zen 3", "7763|7V73|Zen 3", "decide"),
        ("Intel", "Intel|Xeon", "gate"), ("Cobalt", "Neoverse|Cobalt|ARM|aarch64|N2", "gate")]
DECIDE_T = (1, 4)


def verdict(results, stats, noisy):
    """HILL-CLIMB.md acceptance rule from 2026-10-11 (per thread): decide at 1T and 4T on Zen 5
    and Zen 3; Intel AVX2 and Cobalt are gates; all-threads is recorded, not decided."""
    roles, wrong = {}, []
    for res in results:
        size = os.path.basename(res["file"]).split(".")[0]
        want = SIZE_CHIP.get(size)
        if want and not re.search(want, res["machine"] or ""):
            wrong.append(f"{res['file']} is {res['machine']}, not {want}")
            continue
        for name, pat, role in ROLE:
            if re.search(pat, res["machine"] or ""):
                roles.setdefault(name, []).append(res["file"])
                break
    for w in wrong:
        print(f"\nWRONG CHIP (not counted): {w}")
    if noisy:
        print("\nNOISY: the champion differs from itself beyond 0.5% on " + "; ".join(noisy)
              + ". Treat this machine's result as inconclusive and rerun it, ideally on another node.")
    losses, notes, best, rounds = [], [], {}, 0
    for name, pat, role in ROLE:
        for f in roles.get(name, []):
            for (ff, t), (lo, mu, sd, n, is_all) in stats.items():
                if ff != f:
                    continue
                rounds = max(rounds, n)
                if t in DECIDE_T:
                    if mu <= 1 - REGRESS:
                        losses.append(f"{name} {t}T {pct(mu)}")
                    if role == "decide" and (name not in best or lo > best[name][0]):
                        best[name] = (lo, mu, sd, n, t)
                elif is_all and mu < 0.95:
                    notes.append(f"{name} all threads ({t}T) {pct(mu)}: report to Chris, not a revert")
    for nm in ("Zen 5", "Zen 3"):
        if nm not in best:
            print(f"\nWARNING: no {nm} log at 1T/4T; HILL-CLIMB.md needs Zen 3 and Zen 5 for a decision.")
    for n_ in notes:
        print(f"\nRECORDED: {n_}")
    gates = [g for g in ("Intel", "Cobalt") if g in roles]
    print("\nDeciding (best of 1T/4T, lower bound / mean): " + "; ".join(
        f"{k} {t}T {pct(lo)} / {pct(mu)}" for k, (lo, mu, sd, n, t) in best.items())
        + (f". Gates present: {', '.join(gates)}" if gates else ". No gate logs"))
    if not best:
        print("\nVERDICT: NO DATA")
        return
    if losses:
        v = f"REVERT (loses 1% or more at 1T/4T: {'; '.join(losses)})"
    elif len(best) == 2 and min(b[0] for b in best.values()) >= 1 + THRESH:
        v = "KEEP (lower bound >= +1% at 1T or 4T on both Zen 5 and Zen 3; no 1T/4T loss on any machine)"
    elif any(b[1] + (b[1] - b[0]) < 1 + THRESH for b in best.values()) or rounds >= MAX_ROUNDS:
        v = "REVERT (the interval can't reach +1% at 1T or 4T on both Zens, or the round limit is reached)"
    else:
        est = []
        for k, (lo, mu, sd, n, t) in best.items():
            if lo < 1 + THRESH and mu > 1 + THRESH and sd > 0:
                need = (2.1 * sd / (mu - 1 - THRESH)) ** 2
                est.append(f"{k} {t}T about {min(MAX_ROUNDS, max(n + 2, int(need + 0.999)))}")
        v = f"MORE ROUNDS (the interval straddles +1%; rounds needed: {'; '.join(est) or f'up to {MAX_ROUNDS}'})"
    print(f"\nVERDICT: {v}")

if __name__ == "__main__":
    main(sys.argv[1:])
