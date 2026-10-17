import sys,re,collections
L=open(sys.argv[1]).read().splitlines()
c1=collections.Counter();c12=collections.Counter()
i=0
while i<len(L):
    if L[i].startswith('#0') and 'alloc_obj' in L[i]:
        f1=re.sub(r'^#1\s+0x[0-9a-f]+ in ','',L[i+1]).split(' (')[0] if i+1<len(L) and L[i+1].startswith('#1') else '?'
        f2=re.sub(r'^#2\s+0x[0-9a-f]+ in ','',L[i+2]).split(' (')[0] if i+2<len(L) and L[i+2].startswith('#2') else '?'
        c1[f1]+=1;c12[(f1,f2)]+=1
    i+=1
print('total',sum(c1.values()),'array_set hits',sum('HIT fai_array_set' in l for l in L))
for k,v in c1.most_common(): print(v,k)
print('--')
for k,v in c12.most_common(): print(v,k)
