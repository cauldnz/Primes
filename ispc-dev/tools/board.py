#!/usr/bin/env python3
"""board.py <board-task output.txt>...: rank the entries of a `board` task (hc-pool.sh kind board).

Every image runs its default command, as the official benchmark does, and prints one line per
variant and thread count. For each output label and thread count this takes the median passes
over the scored rounds (round "warmup" dropped), then prints a 1T ranking and an all-threads
ranking (each label's best multi-threaded line). Faithful 1-bit lines only, as on the leaderboard.
"""
import re, statistics, sys
for path in sys.argv[1:]:
    vals, rnd, img, cpu = {}, None, None, "?"
    for line in open(path):
        if line.startswith("Model name:"): cpu = line.split(":", 1)[1].strip()
        m = re.match(r"== round (\S+) (\S+)", line)
        if m: rnd, img = m.group(1), m.group(2); continue
        p = line.strip().split(";")
        if rnd in (None, "warmup") or len(p) < 5 or not p[1].isdigit(): continue
        tags = p[4]
        if "faithful=yes" not in tags or "bits=1" not in tags: continue
        alg = re.search(r"algorithm=(\w+)", tags); alg = alg.group(1) if alg else "other"
        # several entries share a label (GordonBGood's Nim, Haskell and V), so key by image too
        vals.setdefault((f"{img}: {p[0]}", int(p[3]), alg), []).append(int(p[1]))
    med = {k: statistics.median(v) for k, v in vals.items()}
    rounds = max((len(v) for v in vals.values()), default=0)
    print(f"\n### {cpu} ({path}, up to {rounds} scored rounds)\n")
    one = sorted(((v, k[0], k[2]) for k, v in med.items() if k[1] == 1), reverse=True)
    print("| # | label | algorithm | passes 1T |\n|---|---|---|---|")
    for i, (v, lab, alg) in enumerate(one, 1): print(f"| {i} | {lab} | {alg} | {v:,.0f} |")
    best = {}
    for (lab, t, alg), v in med.items():
        if t > 1 and v > best.get(lab, (0,))[0]: best[lab] = (v, t, alg)
    print("\n| # | label | algorithm | threads | passes, all threads |\n|---|---|---|---|---|")
    for i, (lab, (v, t, alg)) in enumerate(sorted(best.items(), key=lambda x: -x[1][0]), 1):
        print(f"| {i} | {lab} | {alg} | {t} | {v:,.0f} |")
