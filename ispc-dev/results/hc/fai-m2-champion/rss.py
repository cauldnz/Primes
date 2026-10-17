import sys,subprocess,resource,time,json
t=time.time()
r=subprocess.run(sys.argv[1:],capture_output=True,text=True)
ru=resource.getrusage(resource.RUSAGE_CHILDREN)
print(json.dumps({'cmd':sys.argv[1].split('/')[-2]+'/'+sys.argv[1].split('/')[-1],'rc':r.returncode,'maxrss_kb':ru.ru_maxrss,'wall':round(time.time()-t,2),'out':r.stdout.strip().splitlines(),'err':r.stderr.strip()[:200]}))
