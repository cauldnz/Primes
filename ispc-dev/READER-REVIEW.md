# Reader review: a stranger reads it before it goes public

Everything the machine writes is written by agents that carry the whole run in their context:
the ledger, the jargon, the names, the last twelve hours of decisions. Text written that way reads
fine to its authors and loses everyone else. The first draft of the climb map used "1T",
"dense resets", "hand over at 256" and "0 + 2g" without noticing; a cold reader found about 40
such places in one pass.

So nothing goes public until a reader who doesn't share that context has read it.

## The rule

1. **What it covers:** anything people outside the run will read. READMEs, pull request and issue
   text, the climb map, the docs, published reports, posts. Not the ledger, logs or status
   files, which are records, not reading.
2. **Who reads:** a fresh agent with none of the session's context. Never the session that wrote
   the text, and never one briefed with the author's view of what's good about it.
3. **What it has read first:** the reviewer simulates a particular person arriving at the text.
   Seed it with what that person would already have read, and nothing else:
   - a cold visitor to the climb map or the repo: nothing;
   - a maintainer reading our pull request: the contest's README and CONTRIBUTING.md, the
     category rules, and the existing entries we compare against;
   - a reader of a doc linked from the map: the map's introduction;
   - a reader of an upstream issue: the issue tracker's recent threads on the same rule.
   If in doubt, seed less. A reader who knows too much hides the same gaps the author has.
4. **What it gets:** the rendered output (screenshots or the built page), the reader it plays
   (role, what they know, why they came), the prior reading, and the questions below. It doesn't
   get the author's conclusions.
5. **What it reports:** what the reader couldn't say after the first screen; every term, name or
   number they'd stumble on; where the figures or claims disagree; anything that reads as puffed
   up or as insider talk; the five fixes that matter most, each concrete.
6. **Then:** fix, and if the fixes were large, run a second fresh reader. The first reader can't
   be fresh twice.
7. **Record it:** one line in the build log or the run's report: who the reader was, what it had
   read, and what changed.

## The brief

Copy this, fill in the brackets, and send it to a fresh agent.

```
You are reviewing [the document] for clarity. Read it as [the reader: role, what they know,
why they came]. Before this, you have read [prior reading, with paths or links], and nothing
else about this project. Report what that reader would not understand.

The document: [path or URL]. [How to render it, if it's a page.]

Report, in plain prose and short lists, about 600 words:
1. After the first screen, could the reader say what this is, what was achieved and why it
   matters? What is missing?
2. Every term, abbreviation, name or number the reader would stumble on (quote it, say where).
   Most visible first: titles, labels, numbers.
3. [For a figure: can they tell what each mark, line and axis means?]
4. Contradictions, puffery, or language from inside the team.
5. Your top five fixes, most important first, each concrete.

Be blunt and specific. Don't praise. Don't redesign unless it blocks understanding.
```
