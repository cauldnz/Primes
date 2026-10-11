#!/usr/bin/env python3
"""Rank official Primes results the way the contest's report does.

Usage:
  python3 tools/rank.py SESSION.json [SESSION.json ...] [--algorithm base] [--faithful yes]
                        [--bits 1] [--top 10] [--add "label,passes,duration,threads"]

SESSION.json is a PrimeView session's results (a list of result objects, or an object with a
"results" or "data" list), as saved under results/leaderboard-*/. The ranking copies
tools/src/formatters/table.ts upstream: results split into a single-threaded table
(threads == 1) and a multi-threaded table (threads > 1), each sorted by
passes / duration / threads, highest first. So a 4-thread line competes per thread with a
192-thread line, and usually beats it.

--add puts a line of our own into both tables, for "where would we slot?" questions. Its
algorithm, faithful and bits are taken as passing the filters. Our Azure numbers are passes in
5 seconds on our nodes, not the runner's; scale them by our ratio to a rival measured in the same
rounds before adding them, or the comparison means little (docs/measurement.md in the
hill-climber repo).
"""
import argparse, json, sys


def load(path):
    d = json.load(open(path))
    if isinstance(d, dict):
        d = d.get("results") or d.get("data") or []
    return d


def truthy(v):
    return str(v).lower() in ("true", "yes", "1")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("sessions", nargs="+")
    ap.add_argument("--algorithm")
    ap.add_argument("--faithful", choices=["yes", "no"])
    ap.add_argument("--bits")
    ap.add_argument("--top", type=int, default=10)
    ap.add_argument("--add", action="append", default=[],
                    help='"label,passes,duration,threads" for a line of our own')
    a = ap.parse_args()

    for path in a.sessions:
        rows = []
        for r in load(path):
            if a.algorithm and r.get("algorithm") != a.algorithm:
                continue
            if a.faithful and truthy(r.get("faithful")) != (a.faithful == "yes"):
                continue
            if a.bits and str(r.get("bits")) != a.bits:
                continue
            rows.append({"name": f"{r.get('implementation')}/{r.get('solution')} {r.get('label')}",
                         "passes": r["passes"], "duration": r["duration"], "threads": r["threads"],
                         "ours": False})
        for s in a.add:
            label, passes, duration, threads = [x.strip() for x in s.split(",")]
            rows.append({"name": label, "passes": float(passes), "duration": float(duration),
                         "threads": int(threads), "ours": True})
        for r in rows:
            r["pps"] = r["passes"] / r["duration"] / r["threads"]  # table.ts: passesPerSecond
        print(f"== {path}")
        for title, part in (("Single-threaded", [r for r in rows if r["threads"] == 1]),
                            ("Multi-threaded", [r for r in rows if r["threads"] > 1])):
            part.sort(key=lambda r: r["pps"], reverse=True)
            print(f"  {title}")
            for i, r in enumerate(part[: a.top], 1):
                mark = "  <- added" if r["ours"] else ""
                print(f"  {i:3d}  {r['pps']:12,.0f}  @{r['threads']:<4d} {r['name'][:60]}{mark}")
            ours = [i for i, r in enumerate(part, 1) if r["ours"]]
            if ours and ours[0] > a.top:
                print(f"       ... added line ranks {ours[0]} of {len(part)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
