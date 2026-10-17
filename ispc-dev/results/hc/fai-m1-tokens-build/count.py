import sys,re,tiktoken
def strip(src,lang):
    if lang=='ml':
        out=[];i=0;d=0;instr=False
        while i<len(src):
            if d==0 and src[i]=='"' and not (i>0 and src[i-1]=='\\'):
                instr=not instr; out.append(src[i]); i+=1; continue
            if not instr and src.startswith('(*',i): d+=1;i+=2;continue
            if d and src.startswith('*)',i): d-=1;i+=2;continue
            if d:
                if src[i]=='\n': out.append('\n')
                i+=1;continue
            out.append(src[i]);i+=1
        return ''.join(out)
    # C-like / fai: // and /* */ (fai has only //)
    s=re.sub(r'/\*.*?\*/',lambda m:'\n'*m.group(0).count('\n'),src,flags=re.S)
    s=re.sub(r'(^|[^:"])//.*$',r'\1',s,flags=re.M)
    return s
encs={e:tiktoken.get_encoding(e) for e in ('o200k_base','cl100k_base')}
print(f"{'file':40} {'bytes':>7} {'lines':>6} {'nbnc':>6} {'o200k':>7} {'o200k_nc':>8} {'cl100k':>7}")
for spec in sys.argv[1:]:
    path,lang=spec.rsplit(':',1)
    src=open(path,encoding='utf-8').read()
    nc=strip(src,lang)
    ncl=[l for l in nc.split('\n') if l.strip()]
    nctext='\n'.join(l.rstrip() for l in ncl)
    o=encs['o200k_base']; c=encs['cl100k_base']
    print(f"{path.split('/')[-1]:40} {len(src.encode()):7} {src.count(chr(10)):6} {len(ncl):6} {len(o.encode(src)):7} {len(o.encode(nctext)):8} {len(c.encode(src)):7}")
