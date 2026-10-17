import subprocess, time, sys, os
d=sys.argv[1]
for r in range(2):
    for b in ("st","cc"):
        t=time.time(); out=subprocess.run([os.path.join(d,b,"repro")],capture_output=True,text=True).stdout.strip(); print(b, round(time.time()-t,2), out)
for b in ("st","cc"):
    dis=subprocess.run(["objdump","-d","--no-show-raw-insn",os.path.join(d,b,"repro")],capture_output=True,text=True).stdout
    print(b, "calls array_set", dis.count("<fai_array_set>")-1, "get_borrowed", dis.count("<fai_array_get_borrowed>")-1, "fai_dup", dis.count("call") and dis.count("<fai_dup>"))
