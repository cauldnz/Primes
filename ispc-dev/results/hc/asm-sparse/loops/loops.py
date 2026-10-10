import sys,re
fn=sys.argv[1]; minor=int(sys.argv[2]) if len(sys.argv)>2 else 8
lines=open(fn).read().split('\n')
# keep only first copy: stop at second '## selected' block after a '=='
cur=None; funcs=[]; seen=set()
for l in lines:
    if l.startswith('== '):
        cur=[l[3:],[]]; funcs.append(cur); continue
    m=re.match(r'\s*([0-9a-f]+):\s+(.*)',l)
    if m and cur: cur[1].append((int(m.group(1),16),m.group(2).strip()))
done=set()
for name,ins in funcs:
    addrs=[a for a,_ in ins]
    for i,(a,t) in enumerate(ins):
        m=re.match(r'(j\w+)\s+([0-9a-f]+)',t)
        if m and m.group(1)!='jmpq' or (m and True):
            if not m: continue
            tgt=int(m.group(2),16)
            if tgt<=a and tgt in addrs:
                j=addrs.index(tgt); body=ins[j:i+1]
                n_or=sum(1 for _,x in body if re.match(r'or[bwlq]?\s',x) and ',' in x and '(' in x.split(',',1)[1])
                key=(name[:40],tgt,a)
                if n_or>=minor and len(body)<=int(sys.argv[3]) and key not in done:
                    done.add(key)
                    print(f'### {name[:110]}  loop {tgt:x}-{a:x} insns={len(body)} rmw_or={n_or}')
