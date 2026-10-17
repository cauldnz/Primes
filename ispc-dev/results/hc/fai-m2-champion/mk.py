import re
d='<scratch>/'
p=open(d+'src/PrimeFai/solution_1/Primes.fai').read()
q=open(d+'src/PrimeFai/solution_1/PrimesParallel.fai').read()
def noex(s): return ''.join(l for l in s.splitlines(True) if not re.match(r'\s*(example:|forall\b)',l))
for name,s in [('fai009_Primes.fai',p),('fai009_Primes+Parallel.fai',p+q),('fai009_Primes_noex.fai',noex(p)),('fai009_Primes+Parallel_noex.fai',noex(p)+noex(q))]:
    open(d+'tok/'+name,'w').write(s)
print(sum(1 for l in p.splitlines() if re.match(r'\s*(example:|forall\b)',l)), sum(1 for l in q.splitlines() if re.match(r'\s*(example:|forall\b)',l)))
