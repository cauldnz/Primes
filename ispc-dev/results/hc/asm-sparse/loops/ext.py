import re,sys
src,start,end,out=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
raw=[];on=False
for l in open(src):
    m=re.match(r'\s*([0-9a-f]+):\s+(.*)',l.rstrip('\n'))
    if not m: continue
    if m.group(1)==start: on=True
    if on: raw.append(l.rstrip('\n'))
    if on and m.group(1)==end: break
open(out+'_raw.s','w').write('\n'.join(raw)+'\n')
mca=['.Lloop:']
for l in raw:
    t=re.match(r'\s*[0-9a-f]+:\s+(.*)',l).group(1)
    t=re.sub(r'\s*<[^>]*>','',t)
    t=re.sub(r'^(j[a-z]+)\s+[0-9a-f]+$',r'\1 .Lloop',t)
    mca.append('  '+t)
open(out+'_mca.s','w').write('\n'.join(mca)+'\n')
