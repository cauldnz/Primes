#!/usr/bin/env python3
"""sizecliff.py <size-kind log>...: throughput per number against working set, per entry and thread count.

Labels are w<n> (wheel) and b<n> (base); result lines give passes in ~5 s. Throughput per number
= passes * n / seconds, normalised by n * ln ln n (the sieve's work per number), reported relative
to the smallest size. Working set: wheel 8 * ceil(n/30) bits, base n/16 bytes."""
import math, re, statistics, sys
from collections import defaultdict
for path in sys.argv[1:]:
    machine, rnd, lab = "?", None, None
    data = defaultdict(list)          # (entry, n, threads) -> [normalised rate]
    for line in open(path, errors="replace"):
        if line.startswith("Model name:"): machine = line.split(":", 1)[1].strip()
        m = re.match(r"== round (\S+) (\S+)", line)
        if m: rnd, lab = m.groups(); continue
        p = line.strip().split(";")
        if rnd and rnd != "warmup" and lab and len(p) == 5 and p[1].isdigit():
            n = int(lab[1:]); t = int(p[3])
            data[(lab[0], n, t)].append(int(p[1]) * n / float(p[2]) / t / math.log(math.log(n)))
    print(f"\n### {machine} ({path})\n")
    ts = sorted({k[2] for k in data})
    for e, name, ws in (("w", "wheel", lambda n: 8 * math.ceil(n / 30) / 8 / 1024), ("b", "base", lambda n: n / 16 / 1024)):
        sizes = sorted({k[1] for k in data if k[0] == e})
        if not sizes: continue
        print(f"{name}: per-thread throughput per number, relative to {sizes[0]:,} (1.000)\n")
        print("| n | working set KB | " + " | ".join(f"{t}T" for t in ts) + " |")
        print("|---|---|" + "---|" * len(ts))
        base = {t: statistics.median(data[(e, sizes[0], t)]) for t in ts if data.get((e, sizes[0], t))}
        for n in sizes:
            cells = [f"{statistics.median(data[(e, n, t)]) / base[t]:.3f}" if data.get((e, n, t)) and t in base else "-" for t in ts]
            print(f"| {n:,} | {ws(n):.1f} | " + " | ".join(cells) + " |")
        print()
