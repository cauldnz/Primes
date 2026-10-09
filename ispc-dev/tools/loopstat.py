#!/usr/bin/env python3
"""loopstat.py <file.s> [min-vector-ors]: list the hot loops in an assembly file.

For each backward-branch loop with at least N vector ORs (default 8), prints its length in
instructions, stack reloads and spills, sign extensions, masked moves and memory ORs. Works on
ISPC/LLVM (AT&T) and Zig (Intel) output. A screen, not a verdict: hc-035 cut 24 instructions a
step and gained 0.5% at 1T; hc-033 looked fine and lost 4%.
"""
import re, sys
path = sys.argv[1]; need = int(sys.argv[2]) if len(sys.argv) > 2 else 8
L = open(path).read().split('\n')
lab = {m.group(1): i for i, l in enumerate(L) if (m := re.match(r'^(\.LBB\w+):', l))}
seen = set()
for i, l in enumerate(L):
    m = re.match(r'\s+j\w+\s+(\.LBB\w+)', l)
    if not m or m.group(1) not in lab or lab[m.group(1)] >= i or m.group(1) in seen:
        continue
    body = [x for x in L[lab[m.group(1)]:i + 1]
            if x.strip() and not x.strip().startswith(('#', '.')) and not x.endswith(':')]
    vor = sum(1 for b in body if re.match(r'\s+vp?or', b))
    mem_or = sum(1 for b in body if re.match(r'\s+or[bwlq]?\s', b) and ('(' in b or '[' in b))
    if vor < need and mem_or < need:
        continue
    seen.add(m.group(1))
    c = lambda pat: sum(1 for b in body if re.search(pat, b))
    print(f"{m.group(1)} line {lab[m.group(1)]+1}: {len(body)} instr, vor {vor}, mem-or {mem_or}, "
          f"reload {c('Reload|\\[rsp')}, spill {c('Spill')}, sext {c('movslq|movsxd')}, "
          f"masked {c('vmaskmov|\\{%k')}")
