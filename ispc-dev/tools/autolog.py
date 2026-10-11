#!/usr/bin/env python3
"""autolog.py: write the status page's log from what changed, so it never depends on the climber
remembering to call `st.py event`.

  autolog.py diff        compare the last committed status.json with the working copy, append an
                         event for each change to status.json and to results/hc/EVENTS.jsonl.
                         pub.sh runs this before every commit.
  autolog.py backfill [SINCE]  with SINCE (UTC stamp), append only the missing events after it;
                         without it, rebuild results/hc/EVENTS.jsonl from the whole git history of
                         status.json (each change stamped with its commit time), merged with the
                         events written by hand. Safe to rerun.

What counts as a change: a new experiment, a verdict change (with deltas and the note), the
current experiment moving phase, a scoreboard number moving, and the run changing state.
Heartbeats and spend refreshes are not logged. A new experiment or verdict with no `st.py decide`
event since the last publish gets a warning in the log, so missing reasoning shows.
"""
import json, os, subprocess, sys, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
DEV = os.path.dirname(HERE)
ROOT = os.path.dirname(DEV)
STATUS = os.path.join(DEV, "status.json")
FULL = os.path.join(DEV, "results", "hc", "EVENTS.jsonl")
KEEP = 50


def pct(x):
    return f"{x:+.1f}%" if isinstance(x, (int, float)) else "?"


def changes(old, new):
    """Yield (level, text) for each meaningful difference between two status.json dicts."""
    old = old or {}
    ro, rn = old.get("run") or {}, new.get("run") or {}
    if rn.get("id") and rn.get("id") != ro.get("id"):
        yield "info", f"Run {rn['id']} started ({rn.get('mode', '?')} mode)."
    elif rn.get("state") and rn.get("state") != ro.get("state"):
        spend = rn.get("spend_nzd")
        yield "info", f"Run {rn.get('id', '?')} is {rn['state']}" + (f"; spend NZ${spend}." if spend is not None else ".")

    xo = {x.get("id"): x for x in old.get("experiments") or []}
    for x in new.get("experiments") or []:
        i, v = x.get("id"), x.get("verdict")
        p = xo.get(i)
        if p is None:
            yield "info", f"{i} ({x.get('entry', '?')}) {v}: {x.get('hypothesis', '')}"
        elif v != p.get("verdict"):
            d = ""
            if "delta_1t" in x or "delta_mt" in x:
                d = f" {pct(x.get('delta_1t'))} 1T, {pct(x.get('delta_mt'))} all threads."
            note = x.get("note") or ""
            lvl = "warn" if v in ("inconclusive", "failed") else "info"
            yield lvl, f"{i} {v}.{d} {x.get('where', '')}. {note}".replace("..", ".").replace(" .", ".").strip()

    co, cn = old.get("current") or {}, new.get("current") or {}
    if cn and (cn.get("id"), cn.get("phase")) != (co.get("id"), co.get("phase")):
        yield "info", f"{cn.get('id')}: {cn.get('phase')}. {cn.get('detail', '')}".strip()

    so = {(s.get("machine"), s.get("entry")): s for s in old.get("scoreboard") or []}
    for s in new.get("scoreboard") or []:
        p = so.get((s.get("machine"), s.get("entry")))
        if p and (p.get("ours_1t"), p.get("ours_mt")) != (s.get("ours_1t"), s.get("ours_mt")):
            yield "info", (f"Scoreboard, {s['entry']} on {s['machine']}: {p.get('ours_1t')} → {s.get('ours_1t')} at 1T, "
                           f"{p.get('ours_mt')} → {s.get('ours_mt')} at {s.get('threads', '?')} threads.")


def git(*a):
    return subprocess.run(["git", "-C", ROOT, *a], capture_output=True, text=True).stdout


def load_rev(rev):
    out = git("show", f"{rev}:ispc-dev/status.json")
    try:
        return json.loads(out)
    except Exception:
        return None


def append_full(evs):
    os.makedirs(os.path.dirname(FULL), exist_ok=True)
    with open(FULL, "a") as f:
        for e in evs:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")


def cmd_diff():
    # Compare with status.json as of the last commit that wrote the full log, not HEAD: a commit
    # of status.json made outside pub.sh must not hide its changes from the log (ap-20261011T0100Z
    # lost 01:11-02:26 that way).
    base = git("log", "-1", "--format=%H", "--", "ispc-dev/results/hc/EVENTS.jsonl").strip() or "HEAD"
    old, new = load_rev(base), json.load(open(STATUS))
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    evs = [{"utc": now, "level": l, "text": t, "auto": True} for l, t in changes(old, new)]
    # events added by hand since the last commit go to the full log too
    seen = {(e.get("utc"), e.get("text")) for e in (old or {}).get("events") or []}
    manual = [e for e in new.get("events") or [] if (e.get("utc"), e.get("text")) not in seen]
    # a verdict or a new experiment with no reasoning recorded since the last publish is flagged
    decided = {e.get("id") for e in manual if e.get("level") == "decision"}
    for l, t in list(changes(old, new)):
        xid = t.split(" ", 1)[0].rstrip(":")
        if xid.startswith(("hc-", "z")) and xid not in decided and not any(
                e.get("level") == "decision" and xid in (e.get("text") or "") for e in manual):
            evs.append({"utc": now, "level": "warn", "auto": True,
                        "text": f"{xid} changed with no reasoning recorded (st.py decide)."})
            decided.add(xid)
    if not evs and not manual:
        return
    new["events"] = ((new.get("events") or []) + evs)[-KEEP:]
    json.dump(new, open(STATUS, "w"), indent=2, ensure_ascii=False)
    append_full(manual + evs)
    for e in evs:
        print("log:", e["text"])


def cmd_backfill(since=None):
    """With since (a UTC stamp), append only events after it to the full log instead of rewriting it."""
    revs = git("log", "--reverse", "--format=%H %cI", "--", "ispc-dev/status.json").split("\n")
    out, prev, seen = [], None, set()
    for line in filter(None, revs):
        h, when = line.split(" ", 1)
        cur = load_rev(h)
        if cur is None:
            continue
        utc = datetime.datetime.fromisoformat(when).astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        for e in cur.get("events") or []:
            k = (e.get("utc"), e.get("text"))
            if k not in seen:
                seen.add(k); out.append(e)
        if prev is not None:
            for l, t in changes(prev, cur):
                out.append({"utc": utc, "level": l, "text": t, "auto": True})
        prev = cur
    out.sort(key=lambda e: e.get("utc") or "")
    if since:
        have = set()
        if os.path.exists(FULL):
            for line in open(FULL):
                try:
                    e = json.loads(line); have.add((e.get("utc"), e.get("text")))
                except Exception:
                    pass
        add = [e for e in out if (e.get("utc") or "") > since and (e.get("utc"), e.get("text")) not in have]
        append_full(add)
        print(f"appended {len(add)} events after {since} -> {os.path.relpath(FULL, ROOT)}")
        return
    os.makedirs(os.path.dirname(FULL), exist_ok=True)
    with open(FULL, "w") as f:
        for e in out:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
    print(f"{len(out)} events from {len(revs)} versions of status.json -> {os.path.relpath(FULL, ROOT)}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "diff"
    if cmd == "backfill":
        cmd_backfill(sys.argv[2] if len(sys.argv) > 2 else None)
    else:
        {"diff": cmd_diff}[cmd]()
