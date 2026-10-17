import subprocess
d='<scratch>/'
for i in range(3):
  for b in ['bfai/primes','bfai/primes-parallel','bml/primes']:
    subprocess.run(['python3','-I',d+'scripts/rss.py',d+b])
