import sys,itertools
N=400000
s=bytearray([1])*(N+1); s[0]=s[1]=0
for i in range(2,int(N**.5)+1):
  if s[i]: s[i*i::i]=bytearray(len(s[i*i::i]))
c=list(itertools.accumulate(s))
print(sys.argv[1],'bad',sum(1 for l in open(sys.argv[1]) if c[int(l.split()[0])]!=int(l.split()[1])))
