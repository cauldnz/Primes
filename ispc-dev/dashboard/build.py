#!/usr/bin/env python3
"""Render ispc-dev/status.json into a self-contained, mobile-first HTML status page.

Usage: python3 ispc-dev/dashboard/build.py [status.json] [out.html]
Defaults: ispc-dev/status.json -> ispc-dev/dashboard/out/index.html
No dependencies beyond the standard library. The page refreshes itself every two minutes.
"""
import html, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "status.json")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "out", "index.html")
FULL = os.path.join(os.path.dirname(os.path.abspath(SRC)), "results", "hc", "EVENTS.jsonl")
CSS_ROOT = """:root{--bg:#f6f5f2;--card:#fff;--ink:#1d1d1b;--muted:#6b6a66;--line:#e4e2dc;--up:#1f7a4d;--down:#b3261e;--accent:#2e5496;--warn:#9a6700}
@media (prefers-color-scheme:dark){:root{--bg:#141413;--card:#1e1e1c;--ink:#ecebe7;--muted:#9c9a94;--line:#33322f;--up:#5cc28d;--down:#f28b82;--accent:#8ab4f8;--warn:#f2c94c}}
*{box-sizing:border-box} body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;padding:16px}
main{max-width:760px;margin:0 auto} h1{font-size:20px;margin:4px 0 2px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px;margin:12px 0} .sub{color:var(--muted);font-size:13px}"""
PHASES = ["hypothesis", "plan", "implement", "gate", "evaluate", "decide"]

e = lambda v: html.escape("" if v is None else str(v))

def num(n):
    if n is None: return "–"
    return f"{n/1e6:.2f}M" if n >= 1e6 else f"{n/1e3:.1f}k"

def margin(ours, rival):
    if not ours or not rival: return None
    return (ours / rival - 1) * 100

def mline(label, ours, rival):
    m = margin(ours, rival)
    if m is None:
        mm, cls, w = "–", "", 0
    else:
        mm, cls, w = f"{m:+.0f}%", ("up" if m >= 0 else "down"), min(abs(m), 40) / 40 * 100
    return (f'<div class="ml {cls}"><span class="lab">{label}</span>'
            f'<span class="nums"><b>{num(ours)}</b> vs {num(rival)}</span>'
            f'<span class="bar"><i style="width:{w:.0f}%"></i></span><b class="pct">{mm}</b></div>')

def scoreboard(rows, entry):
    rs = [r for r in rows if r.get("entry") == entry]
    if not rs: return ""
    rival = e(rs[0].get("rival"))
    body = "".join(
        f'<div class="mach"><div class="mname">{e(r["machine"])}</div>'
        f'{mline("1 thread", r.get("ours_1t"), r.get("rival_1t"))}'
        f'{mline(e(r.get("threads", "all")) + " threads", r.get("ours_mt"), r.get("rival_mt"))}</div>'
        for r in rs)
    title = "Wheel (solution_1)" if entry == "wheel" else "Base (solution_2)"
    return (f'<section class="card"><h2>{title}</h2><p class="sub">Passes in 5s, ours vs {rival}</p>{body}</section>')

def current(c):
    if not c:
        return '<section class="card"><h2>Now</h2><p class="muted">No experiment running.</p></section>'
    ph = c.get("phase")
    steps = "".join(
        f'<li class="{"done" if ph in PHASES and PHASES.index(p) < PHASES.index(ph) else ("on" if p == ph else "")}">{p}</li>'
        for p in PHASES)
    return (f'<section class="card"><h2>Now: {e(c.get("id"))}</h2>'
            f'<p><span class="tag">{e(c.get("entry"))}</span> {e(c.get("hypothesis"))}</p>'
            f'<ol class="phases">{steps}</ol>'
            f'<p class="sub">{e(c.get("detail"))} · started <time data-utc="{e(c.get("started_utc"))}"></time></p></section>')

def experiments(xs):
    if not xs:
        return '<section class="card"><h2>Experiments</h2><p class="muted">None yet.</p></section>'
    rows = ""
    for x in reversed(xs):
        v = (x.get("verdict") or "running").lower()
        d1 = x.get("delta_1t"); dm = x.get("delta_mt")
        ds = " / ".join("–" if d is None else f"{d:+.1f}%" for d in (d1, dm))
        rows += (f'<li><div class="row1"><b>{e(x.get("id"))}</b><span class="tag">{e(x.get("entry"))}</span>'
                 f'<span class="v {e(v)}">{e(v)}</span><span class="d">{ds}</span></div>'
                 f'<div class="hyp">{e(x.get("hypothesis"))}</div>'
                 f'<div class="sub">{e(x.get("where"))} · {e(x.get("note"))}</div></li>')
    return f'<section class="card"><h2>Experiments</h2><p class="sub">Newest first. Δ = 1 thread / all threads, against the champion.</p><ul class="xs">{rows}</ul></section>'

def cycles(c):
    """'Where the cycles go': share of cycles per phase for each program, from the profile."""
    if not c:
        return ""
    phases = c.get("phases") or ["dense", "sparse", "scan", "setup"]
    head = "".join(f"<th>{e(p)}</th>" for p in phases)
    body = ""
    for r in c.get("rows", []):
        sh = r.get("share", {})
        cells = "".join(f'<td>{"–" if sh.get(p) is None else f"{sh[p]:.0f}%"}</td>' for p in phases)
        body += f'<tr><th>{e(r.get("program"))}<small>{e(r.get("machine"))}</small></th>{cells}<td>{e(r.get("per_pass"))}</td></tr>'
    notes = "".join(f"<li>{e(n)}</li>" for n in c.get("notes", []))
    return (f'<section class="card"><h2>Where the cycles go</h2><p class="sub">{e(c.get("source"))}</p>'
            f'<div class="scroll"><table><thead><tr><th></th>{head}<th>per pass</th></tr></thead><tbody>{body}</tbody></table></div>'
            f'<ul class="next">{notes}</ul></section>')

def research(r):
    """Background research agent: state, ideas found so far, and the 'other' lane assessment."""
    if not r:
        return ""
    st = (r.get("state") or "idle").lower()
    when = r.get("done_utc") if st == "done" else r.get("started_utc")
    rows = ""
    for i in r.get("ideas", []):
        bl = i.get("backlog")
        blt = {True: "in backlog", False: "not adopted"}.get(bl, bl or "under review")
        rows += (f'<li><div class="row1"><b>{e(i.get("title"))}</b><span class="tag">{e(i.get("entry"))}</span>'
                 f'<span class="tag">{e(i.get("phase"))}</span><span class="d">{e(i.get("gain"))}</span></div>'
                 f'<div class="hyp">{e(i.get("summary"))}</div><div class="sub">{e(blt)}</div></li>')
    ideas = f'<ul class="xs">{rows}</ul>' if rows else '<p class="muted">No ideas reported yet.</p>'
    ol = r.get("other_lane") or {}
    other = (f'<h2 style="margin-top:12px">"Other" lane (solution_3)</h2><p>{e(ol.get("assessment"))}</p>'
             f'<p><b>Recommendation:</b> {e(ol.get("recommendation"))}</p>') if ol else \
            '<p class="sub">"Other" lane assessment: pending.</p>'
    return (f'<section class="card"><h2>Research</h2><div class="status"><span class="pill {"running" if st == "running" else ""}">{e(st)}</span>'
            f'<span class="sub">{"finished" if st == "done" else "started"} <time data-utc="{e(when)}"></time></span></div>'
            f'<p class="sub">{e(r.get("note"))}</p>{ideas}{other}</section>')

def events(evs):
    items = "".join(
        f'<li class="{e(v.get("level"))}"><time data-utc="{e(v.get("utc"))}"></time>{e(v.get("text"))}</li>'
        for v in list(reversed(evs))[:25])
    full = ('<p class="sub" style="margin:10px 0 0"><a href="log.html">The whole log, every run since 9 October →</a></p>'
            if os.path.exists(FULL) else "")
    return f'<section class="card"><h2>Log</h2><ul class="log">{items}</ul>{full}</section>'

def build_log(evs):
    """log.html: every event from results/hc/EVENTS.jsonl, newest first, grouped by AEST day."""
    rows = []
    for v in reversed(evs):
        rows.append(f'<li class="{e(v.get("level"))}"><time data-utc="{e(v.get("utc"))}"></time>{e(v.get("text"))}</li>')
    css = CSS_ROOT + """
.log{list-style:none;padding:0;margin:0} .log li{font-size:13px;padding:5px 0;border-top:1px solid var(--line)}
.log time{color:var(--muted);margin-right:8px;font-variant-numeric:tabular-nums;white-space:nowrap}
.log .warn{color:var(--warn)} .log .error{color:var(--down)} a{color:var(--accent)} .log .decision{border-left:3px solid var(--accent);padding-left:8px}"""
    return f"""<!doctype html>
<html lang="en-AU"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta http-equiv="refresh" content="300">
<title>ISPC autopilot log</title><style>{css}</style></head><body><main>
<header class="card"><h1>The whole log</h1>
<p class="sub">{len(evs)} events from every run, newest first. Rebuilt from the git history of status.json, so
nothing a run forgot to log is missing. <a href="index.html">← Status</a></p></header>
<section class="card"><ul class="log">{"".join(rows)}</ul></section>
<footer class="sub" style="text-align:center">Generated from ispc-dev/results/hc/EVENTS.jsonl on cauldnz/Primes.</footer>
</main><script>
const fmt=new Intl.DateTimeFormat('en-AU',{{timeZone:'Australia/Brisbane',weekday:'short',day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}});
document.querySelectorAll('time[data-utc]').forEach(t=>{{const d=new Date(t.dataset.utc);t.textContent=isNaN(d)?'–':fmt.format(d);}});
</script></body></html>
"""

def build(s):
    run = s.get("run", {})
    state = (run.get("state") or "idle").lower()
    spend, cap = run.get("spend_nzd") or 0, run.get("spend_cap_nzd") or 0
    spend_w = min(spend / cap, 1) * 100 if cap else 0
    nxt = "".join(f"<li>{e(n)}</li>" for n in s.get("next_up", []))
    return f"""<!doctype html>
<html lang="en-AU"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta http-equiv="refresh" content="120">
<title>ISPC autopilot</title>
<style>
:root{{--bg:#f6f5f2;--card:#fff;--ink:#1d1d1b;--muted:#6b6a66;--line:#e4e2dc;--up:#1f7a4d;--down:#b3261e;--accent:#2e5496;--warn:#9a6700;--warnbg:#fff4d6}}
@media (prefers-color-scheme:dark){{:root{{--bg:#141413;--card:#1e1e1c;--ink:#ecebe7;--muted:#9c9a94;--line:#33322f;--up:#5cc28d;--down:#f28b82;--accent:#8ab4f8;--warn:#f2c94c;--warnbg:#3a3020}}}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;padding:16px 16px calc(16px + env(safe-area-inset-bottom))}}
main{{max-width:760px;margin:0 auto}}
h1{{font-size:20px;margin:4px 0 2px}} h2{{font-size:16px;margin:0 0 6px}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px;margin:12px 0}}
.sub,.muted,small{{color:var(--muted);font-size:13px}} small{{display:block}}
.status{{display:flex;flex-wrap:wrap;gap:8px;align-items:center}}
.pill{{border-radius:999px;padding:3px 10px;font-weight:600;font-size:13px;border:1px solid var(--line)}}
.pill.running{{color:var(--up);border-color:var(--up)}} .pill.stopped,.pill.failed{{color:var(--down);border-color:var(--down)}}
.stale{{display:none;background:var(--warnbg);color:var(--warn);border-radius:8px;padding:8px 10px;margin-top:8px;font-size:14px}}
.meter{{height:6px;background:var(--line);border-radius:3px;overflow:hidden;margin-top:4px}} .meter i{{display:block;height:100%;background:var(--accent)}}
.kv{{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:10px}} .kv div{{font-size:13px;color:var(--muted)}} .kv b{{display:block;color:var(--ink);font-size:15px}}
.scroll{{overflow-x:auto}} table{{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}}
th,td{{text-align:left;padding:7px 6px;border-top:1px solid var(--line);font-size:14px;vertical-align:top}}
thead th{{border-top:0;color:var(--muted);font-weight:500;font-size:12px}} tbody th{{font-weight:500;white-space:nowrap}}
td.m{{white-space:nowrap}} td.m b{{font-size:13px;margin-left:6px}} .up b{{color:var(--up)}} .down b{{color:var(--down)}}
.bar{{display:inline-block;width:38px;height:6px;background:var(--line);border-radius:3px;vertical-align:middle;overflow:hidden}}
.up .bar i{{display:block;height:100%;background:var(--up)}} .down .bar i{{display:block;height:100%;background:var(--down)}}
.mach{{padding:9px 0;border-top:1px solid var(--line)}} .mach:first-of-type{{border-top:0}} .mname{{font-weight:600;font-size:14px;margin-bottom:3px}}
.ml{{display:grid;grid-template-columns:72px 1fr 40px 44px;align-items:center;gap:6px;font-size:13px;font-variant-numeric:tabular-nums;padding:2px 0}}
.ml .lab{{color:var(--muted)}} .ml .nums{{color:var(--muted)}} .ml .nums b{{color:var(--ink);font-weight:600}} .ml .pct{{text-align:right}}
.ml.up .pct{{color:var(--up)}} .ml.down .pct{{color:var(--down)}}
.tag{{font-size:12px;border:1px solid var(--line);border-radius:6px;padding:1px 6px;margin:0 6px;color:var(--muted)}}
.phases{{display:flex;flex-wrap:wrap;gap:6px;list-style:none;padding:0;margin:10px 0}}
.phases li{{font-size:12px;padding:3px 8px;border-radius:6px;border:1px solid var(--line);color:var(--muted)}}
.phases li.done{{color:var(--ink)}} .phases li.on{{background:var(--accent);border-color:var(--accent);color:#fff}}
.xs,.log,.next{{list-style:none;padding:0;margin:0}} .xs li{{padding:10px 0;border-top:1px solid var(--line)}} .xs li:first-child{{border-top:0}}
.row1{{display:flex;align-items:center;gap:4px;flex-wrap:wrap}} .row1 .d{{margin-left:auto;font-variant-numeric:tabular-nums;font-size:13px}}
.hyp{{margin:3px 0}} .v{{font-size:12px;font-weight:600;padding:1px 7px;border-radius:6px;border:1px solid currentColor}}
.v.kept,.v.confirmed{{color:var(--up)}} .v.rejected,.v.reverted,.v.failed{{color:var(--down)}} .v.queued,.v.running{{color:var(--warn)}}
.log li{{font-size:13px;padding:4px 0;border-top:1px solid var(--line)}} .log li:first-child{{border-top:0}}
.log time{{color:var(--muted);margin-right:8px;font-variant-numeric:tabular-nums}} .log .warn{{color:var(--warn)}} .log .error{{color:var(--down)}} .log .decision{{border-left:3px solid var(--accent);padding-left:8px}}
.next li{{padding:4px 0}} .next li::before{{content:"→ ";color:var(--muted)}}
.btn{{display:inline-block;padding:8px 14px;border-radius:8px;border:1px solid var(--accent);color:var(--accent);text-decoration:none;font-weight:600;font-size:14px}}
footer{{color:var(--muted);font-size:12px;text-align:center;margin:18px 0 8px}}
</style></head><body><main>
<header class="card">
  <h1>ISPC autopilot</h1>
  <div class="status"><span class="pill {e(state)}">{e(state)}</span><span class="pill">{e(run.get("mode"))} mode</span>
  <span class="sub">updated <time id="upd" data-utc="{e(s.get("updated_utc"))}"></time></span></div>
  <div class="stale" id="stale">No update for over 45 minutes. The run may have stopped.</div>
  <p class="sub" style="margin:8px 0 0">{e(run.get("mode_reason"))}</p>
  <div class="kv">
    <div>Run<b>{e(run.get("id"))}</b></div>
    <div>Started<b><time data-utc="{e(run.get("started_utc"))}"></time></b></div>
    <div>Azure spend<b>NZ${spend:.2f} of NZ${cap:.0f}</b><div class="meter"><i style="width:{spend_w:.0f}%"></i></div></div>
    <div>Queued for Zen<b>{e(s.get("azure_queue", 0))}</b></div>
    <div>Background runs<b>{e(run.get("background_runs", "–"))}</b></div>
  </div>
</header>
{current(s.get("current"))}
{scoreboard(s.get("scoreboard", []), "wheel")}
{scoreboard(s.get("scoreboard", []), "base")}
{cycles(s.get("cycles"))}
{experiments(s.get("experiments", []))}
{research(s.get("research"))}
<section class="card"><h2>Next up</h2><ul class="next">{nxt}</ul></section>
{events(s.get("events", []))}
<footer>Generated from ispc-dev/status.json on cauldnz/Primes. Refreshes every 2 minutes.</footer>
</main>
<script>
const fmt=new Intl.DateTimeFormat('en-AU',{{timeZone:'Australia/Brisbane',weekday:'short',hour:'2-digit',minute:'2-digit'}});
document.querySelectorAll('time[data-utc]').forEach(t=>{{const v=t.dataset.utc;if(!v||v==='None'){{t.textContent='–';return}}const d=new Date(v);if(isNaN(d)){{t.textContent=v;return}}t.textContent=fmt.format(d)+' AEST';}});
const u=document.getElementById('upd'),d=new Date(u.dataset.utc);
if(!isNaN(d)){{const m=Math.round((Date.now()-d)/60000);u.textContent=(m<1?'just now':m<120?m+' min ago':Math.round(m/60)+' h ago');if(m>45)document.getElementById('stale').style.display='block';}}
</script></body></html>
"""

if __name__ == "__main__":
    with open(SRC) as f: s = json.load(f)
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    with open(OUT, "w") as f: f.write(build(s))
    print(OUT)
    if os.path.exists(FULL):
        evs = [json.loads(l) for l in open(FULL) if l.strip()]
        lo = os.path.join(os.path.dirname(os.path.abspath(OUT)), "log.html")
        with open(lo, "w") as f: f.write(build_log(evs))
        print(lo)
