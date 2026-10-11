#!/usr/bin/env python3
"""tokens.py: count the model tokens a climb used, from Claude Code's own transcripts.

Claude Code writes every model call to ~/.claude/projects/<dir>/<session>.jsonl (sub-agents
under <session>/subagents/), with the call's usage. This reads only those usage fields (never
the content), drops repeated lines of the same call, and totals them by run, using the run
windows in results/hc/EVENTS.jsonl.

  python3 tools/tokens.py [--role climber] [--transcripts GLOB] [--status] [--hc FOLDER]

Writes results/hc/tokens-<role>.json. A session's transcripts live in its own container and
can vanish when the container is reclaimed, so totals only ever grow: a run already counted
keeps its larger count. With --status it also sets status.json's "tokens" field for the page.

The four kinds of input token cost very different amounts, so they are kept apart:
  fresh     input not seen before
  write     input written to the prompt cache
  read      input read back from the cache (the whole conversation, every call; cheap)
  output    what the model wrote
"""
import argparse, glob, json, os, sys
from collections import defaultdict
from datetime import datetime, timezone

HC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KINDS = ("fresh", "write", "read", "output")

def runs_from(events_path):
    import re
    runs = []
    if not os.path.exists(events_path):
        return runs
    cur = {}
    for line in open(events_path):
        try:
            e = json.loads(line)
        except Exception:
            continue
        t = e.get("text", "")
        m = re.search(r"Run (ap-\S+) started", t)
        if m and m.group(1) not in cur:
            cur[m.group(1)] = {"id": m.group(1), "start": e["utc"], "end": None}
        m = re.search(r"Run (ap-\S+) is stopped", t)
        if m:
            r = cur.setdefault(m.group(1), {"id": m.group(1), "start": None, "end": None})
            r["end"] = e["utc"]
            if not r["start"]:
                st = re.match(r"ap-(\d{8})T(\d{4})Z", m.group(1))
                r["start"] = datetime.strptime("".join(st.groups()), "%Y%m%d%H%M").strftime("%Y-%m-%dT%H:%M:00Z") if st else e["utc"]
    runs = sorted(cur.values(), key=lambda r: r["start"])
    return runs

def which_run(ts, runs):
    for r in runs:
        if r["start"] <= ts and (r["end"] is None or ts <= r["end"]):
            return r["id"]
    return "between runs"

def scan(pattern, runs):
    seen = set()
    by = defaultdict(lambda: {"calls": 0, **{k: 0 for k in KINDS}, "models": defaultdict(int), "first": None, "last": None})
    for f in glob.glob(os.path.expanduser(pattern), recursive=True):
        agent = "sub-agents" if "/subagents/" in f else "main"
        for line in open(f, errors="replace"):
            if '"usage"' not in line:
                continue
            try:
                e = json.loads(line)
            except Exception:
                continue
            m = e.get("message")
            if not isinstance(m, dict) or not m.get("usage"):
                continue
            mid = m.get("id") or e.get("uuid")
            if mid in seen:
                continue
            seen.add(mid)
            u = m["usage"]
            ts = (e.get("timestamp") or "")[:19] + "Z"
            b = by[(which_run(ts, runs), agent)]
            b["calls"] += 1
            b["fresh"] += u.get("input_tokens") or 0
            b["write"] += u.get("cache_creation_input_tokens") or 0
            b["read"] += u.get("cache_read_input_tokens") or 0
            b["output"] += u.get("output_tokens") or 0
            b["models"][m.get("model") or "?"] += 1
            b["first"] = min(b["first"] or ts, ts)
            b["last"] = max(b["last"] or ts, ts)
    out = {}
    for (run, agent), b in by.items():
        b["models"] = dict(b["models"])
        out.setdefault(run, {})[agent] = b
    return out

def merge(old, new):
    """Keep, for each run and agent, whichever count saw more calls: transcripts can disappear."""
    for run, agents in new.items():
        for agent, b in agents.items():
            prev = old.get(run, {}).get(agent)
            if not prev or b["calls"] >= prev["calls"]:
                old.setdefault(run, {})[agent] = b
    return old

def totals(runs):
    t = {"calls": 0, **{k: 0 for k in KINDS}}
    for agents in runs.values():
        for b in agents.values():
            for k in t:
                t[k] += b[k]
    t["total"] = sum(t[k] for k in KINDS)
    return t

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--role", default="climber", help="whose transcripts these are (climber, workshop)")
    ap.add_argument("--transcripts", default="~/.claude/projects/**/*.jsonl")
    ap.add_argument("--status", action="store_true", help="also write the totals into status.json")
    ap.add_argument("--hc", default=HC, help="the machine folder (default: this script's parent)")
    a = ap.parse_args()
    hc = os.path.abspath(a.hc)
    runs = runs_from(os.path.join(hc, "results/hc/EVENTS.jsonl"))
    path = os.path.join(hc, f"results/hc/tokens-{a.role}.json")
    old = json.load(open(path)).get("runs", {}) if os.path.exists(path) else {}
    merged = merge(old, scan(a.transcripts, runs))
    doc = {"role": a.role, "updated_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
           "kinds": {"fresh": "new input", "write": "cache writes", "read": "cache reads", "output": "output"},
           "totals": totals(merged), "runs": merged}
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(doc, open(path, "w"), indent=1, sort_keys=True)
    if a.status:
        sp = os.path.join(hc, "status.json")
        s = json.load(open(sp))
        tok = s.setdefault("tokens", {})
        per_run = {}
        for run, agents in merged.items():
            per_run[run] = {k: sum(b[k] for b in agents.values()) for k in ("calls",) + KINDS}
        tok[a.role] = {"totals": doc["totals"], "runs": per_run, "updated_utc": doc["updated_utc"]}
        json.dump(s, open(sp, "w"), indent=2, ensure_ascii=False)
    t = doc["totals"]
    print(f"{a.role}: {t['calls']} calls, {t['total']/1e6:.1f}M tokens "
          f"(reads {t['read']/1e6:.1f}M, writes {t['write']/1e6:.2f}M, new {t['fresh']/1e3:.0f}k, output {t['output']/1e3:.0f}k)")

if __name__ == "__main__":
    main()
