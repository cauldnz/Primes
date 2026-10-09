#!/usr/bin/env -S python3 -W ignore
# st.py <json-patch-python-expr...>: edit ispc-dev/status.json. Usage examples:
#   st.py event "text" [level]
#   st.py decide ID "what I decided" "why" ["what I passed over"] ["what I expect"]
#   st.py current ID PHASE "detail" | st.py current none
#   st.py set run.state running
#   st.py exp '{"id":..}'   (upsert by id)
#   st.py spend
import json, sys, datetime, csv
import os
P=os.path.join(os.path.dirname(os.path.abspath(__file__)),"..","status.json")
d=json.load(open(P)); now=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
a=sys.argv[1:]
if a[0]=="event":
    d["events"].append({"utc":now,"level":a[2] if len(a)>2 else "info","text":a[1]}); d["events"]=d["events"][-50:]
elif a[0]=="decide":
    f=dict(zip(["id","what","why","instead","expect"],a[1:6]))
    t=f"{f.get('id')}: {f.get('what','').rstrip('.')}. Why: {f.get('why','').rstrip('.')}."
    if f.get("instead"): t+=f" Passed over: {f['instead'].rstrip('.')}."
    if f.get("expect"): t+=f" Expect: {f['expect'].rstrip('.')}."
    d["events"].append({"utc":now,"level":"decision","text":t,**{k:v for k,v in f.items() if v}}); d["events"]=d["events"][-50:]
elif a[0]=="current":
    d["current"]=None if a[1]=="none" else {"id":a[1],"phase":a[2],"detail":a[3]}
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
        if x["id"]==e["id"]: x.update(e); break
    else: xs.append(e)
elif a[0]=="spend":
    price={"Standard_D16a_v4":0.13,"Standard_D16as_v5":0.127,"Standard_D16as_v6":0.134,"Standard_D16as_v7":0.134}
    tot=0
    for r in csv.reader(open(os.path.join(os.path.dirname(P),"results","cost-log.csv"))):
        if len(r)<4 or r[0]<d["run"]["started_utc"]: continue
        pl={k.lower():v for k,v in price.items()}; tot+=int(r[3])/60*pl.get(r[2].lower(),0.04)
    d["run"]["spend_nzd"]=round(1.7*tot*1.2,2); print(d["run"]["spend_nzd"])
d["updated_utc"]=now
json.dump(d,open(P,"w"),indent=2,ensure_ascii=False)
