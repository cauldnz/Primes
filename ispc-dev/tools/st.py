#!/usr/bin/env -S python3 -W ignore
# st.py <json-patch-python-expr...>: edit ispc-dev/status.json. Usage examples:
#   st.py event "text" [level]
#   st.py current ID PHASE "detail" | st.py current none
#   st.py set run.state running
#   st.py exp '{"id":..}'   (upsert by id)
#   st.py spend
# The page's Log shows status.json's events. "current" and "exp" add an event themselves whenever
# the current step or an experiment's verdict changes, so the log keeps pace with the run.
import json, sys, datetime, csv
import os
P=os.path.join(os.path.dirname(os.path.abspath(__file__)),"..","status.json")
d=json.load(open(P)); now=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
def log(text, level="info"):
    d["events"].append({"utc":now,"level":level,"text":text}); d["events"]=d["events"][-50:]
a=sys.argv[1:]
if a[0]=="event":
    log(a[1], a[2] if len(a)>2 else "info")
elif a[0]=="current":
    old=d.get("current") or {}
    d["current"]=None if a[1]=="none" else {"id":a[1],"phase":a[2],"detail":a[3]}
    if a[1]!="none" and (old.get("id"),old.get("phase"),old.get("detail"))!=(a[1],a[2],a[3]):
        log(f"{a[1]} ({a[2]}): {a[3]}")
elif a[0]=="set":
    o=d; ks=a[1].split(".")
    for k in ks[:-1]: o=o[k]
    v=a[2]
    try: v=json.loads(v)
    except Exception: pass
    o[ks[-1]]=v
elif a[0]=="exp":
    e=json.loads(a[1]); xs=d["experiments"]
    for i,x in enumerate(xs):
        if x["id"]==e["id"]: before=x.get("verdict"); x.update(e); break
    else: before=None; xs.append(e)
    if e.get("verdict") and e.get("verdict")!=before:
        what=e.get("where") if e["verdict"]!="running" else e.get("hypothesis")
        log(f'{e["id"]} {e["verdict"]}: {what or ""}'.strip(), "warn" if e["verdict"]=="failed" else "info")
elif a[0]=="spend":
    price={"Standard_D16a_v4":0.13,"Standard_D16as_v5":0.127,"Standard_D16as_v6":0.134,"Standard_D16as_v7":0.134}
    tot=0
    for r in csv.reader(open(os.path.join(os.path.dirname(P),"results","cost-log.csv"))):
        if len(r)<4 or r[0]<d["run"]["started_utc"]: continue
        pl={k.lower():v for k,v in price.items()}; tot+=int(r[3])/60*pl.get(r[2].lower(),0.04)
    d["run"]["spend_nzd"]=round(1.7*tot*1.2,2); print(d["run"]["spend_nzd"])
d["updated_utc"]=now
json.dump(d,open(P,"w"),indent=2,ensure_ascii=False)
