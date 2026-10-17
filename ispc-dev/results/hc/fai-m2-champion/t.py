import subprocess,time,os
e=dict(os.environ,PRIMES_TEST='1')
t=time.time();r=subprocess.run(['<scratch>/bfai/primes'],env=e,capture_output=True,text=True)
print(r.returncode,round(time.time()-t,2),r.stdout[-500:],r.stderr[-300:])
