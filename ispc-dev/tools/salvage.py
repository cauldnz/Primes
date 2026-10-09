#!/usr/bin/env python3
"""salvage.py <task.log> <out.txt>: rebuild an analyze.py input from a task's streamed log.

Use when Spot preempts a node mid-task: the rounds already streamed into the local log are
complete measurements. Drops the last, unfinished round and marks the file as partial.
"""
import os, sys
lines = open(sys.argv[1]).read().split('\n')
start = next(i for i, l in enumerate(lines) if l.startswith('Architecture'))
rounds = [i for i, l in enumerate(lines) if l.startswith('== round ')]
first = next(i for i in rounds if i > start)
last_round = lines[rounds[-1]].split()[2]
keep = [i for i in rounds if lines[i].split()[2] == last_round]
done = any(l.startswith('### done') for l in lines)
end = len(lines) if done else keep[0]
header = [l for l in lines[start:first] if not l.startswith(('  ', '###', 'Alive'))]
body = [l for l in lines[first:end] if not l.startswith(('  ', '###', 'Alive'))]
n = len({lines[i].split()[2] for i in rounds if first <= i < end} - {'warmup'})
os.makedirs(os.path.dirname(os.path.abspath(sys.argv[2])), exist_ok=True)
open(sys.argv[2], 'w').write(
    f"# Partial: {n} scored rounds salvaged from {sys.argv[1]}; round {last_round} dropped unless the task finished.\n"
    + '\n'.join(header + body) + '\n')
print(f"{n} scored rounds -> {sys.argv[2]}")
