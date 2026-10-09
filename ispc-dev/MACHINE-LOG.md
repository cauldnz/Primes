# Building a hill-climbing machine: the log

Raw material for a later write-up on building an evaluation-driven hill-climbing machine with
Claude. The ledger records what the machine found; this file records how the machine itself was
built and changed, and why. The workshop (the Claude.ai session) appends to it; newest entries
last. Public, like the rest of the repo.

## The shape of the machine

- **Workshop:** a Claude.ai session with Chris. It handles ideas, monitoring, queueing work and
  changing the machine.
- **Climber:** Claude Code. It started on Chris's laptop and moved to unattended cloud sessions.
  It runs experiments, records them and reports.
- **Evaluation:** Azure Batch Spot pools of AMD Zen 3, 4 and 5 and Arm nodes. Every round
  interleaves the champion, the candidate, the champion again (an A/A noise floor) and a rival
  entry. Round 1 is discarded.
- **State:** everything lives in git. Living files run in each direction (`STATUS.md` from the
  climber, `NEXT-STEPS.md` from the workshop), plus a ledger, a champion branch and a static
  status page.

## Timeline and decisions

### 9 October, afternoon: from one-off tuning to a loop

- Started as a chat: pick a language for the Primes drag race, write a sieve, benchmark it in a
  2-vCPU sandbox. Six sandbox versions took the wheel from 6,300 to about 59,000 passes.
- **The first lesson was about measurement, not code.** Single runs on shared machines swung by
  10%, so every comparison became an interleaved A/B with the previous build. That rule became
  the core of the protocol.
- **Two sessions, passing notes.** Claude Code took over the Azure benchmarking; the sessions
  coordinated through dated notes files in the repo, which turned into the living
  `STATUS.md` and `NEXT-STEPS.md`.

### 9 October, evening: making it run unattended

- **The protocol (`HILL-CLIMB.md`).** Hypothesis with a written prediction, the smallest change,
  a rules and self-test gate, evaluation with controls in every round, then a decision rule set
  in advance: at least 2% on Zen 3 and Zen 5, no regression above 1%. Losers are logged too.
- **A run moved Zen 5 numbers by 17% with no code change.** Round 1 on that VM size was slow for
  every build. Controls in every round caught it; the protocol now discards round 1. Without
  the controls it would have looked like a regression.
- **The brief (`AUTOPILOT.md`)** split "what to aim for and how to judge" from the climber's
  own "how to run it" (`CLOUD-RUNBOOK.md`). Two runbooks written in parallel had to be
  reconciled into one: the brief for judgement, the runbook for mechanics, with the runbook's
  limits winning.
- **A champion branch.** Winners first stayed on their own branches, so gains couldn't stack.
  `hc/champion` collects accepted winners, and every experiment is measured against it.
- **Guardrails:** a spend cap, a time box, "too good to be true" re-checks for gains above 20%,
  and a "never without Chris" list (no PRs, no pushes to the submission branch, no spending past
  the cap).

### 10 October, morning: what the overnight runs taught

- **Results.** About 40 experiments over three runs, roughly a quarter kept, for about NZ$7.
  The wheel gained 16–27% at one thread on Zen and the base entry 24–41%. Most hypotheses
  failed, including the top suggestion from two outside model reviews, which lost 7%.
- **The status page went stale.** The brief told the climber to block in foreground waits so the
  cloud VM wouldn't pause, and nothing updated during them. Fix: the heartbeat moved inside
  the wait command (`tools/wait.sh`), so publishing no longer depends on the agent remembering.
- **Chat messages couldn't reach a running climber.** A whole run is one turn, so messages
  queue. The first fix was a file inbox the climber polled every minute. It worked in a test
  (61 seconds to pick-up), and the running climber, unprompted, treated the file's contents as
  information rather than commands.
- **The inbox was a security hole, and it came out the same morning.** Chris spotted that the
  public page linked to the inbox. The deeper problem: anything able to push to the branch
  (another agent, a GitHub app, a session tricked by text in a web page) could have steered a
  run that holds cloud credentials. Rule now: steering only by direct message, no file is ever
  an instruction channel, and the status page is read-only.
- **The repo is public, history included.** A scan found no secrets but did find an email
  address on over 100 commits, account details in notes and cloud resource names in scripts.
  Standing rules now list what never goes in, and commits use a no-reply identity.
- **No changes under a running climb.** A harness change pushed mid-run was picked up mid-run.
  Rule: a run works from its starting commit; the workshop changes the machine between runs.
- **A port in another language beat the original.** A Zig port of the ISPC wheel was 12–18%
  faster with the same design. That changed the question from "which language wins" to "what
  does the design owe to the language", and led to the plan to run one design in four
  languages.

### 10 October, 09:15: steering by the person, between ticks

- Chris asked for a secure way to steer a climb while it runs. The answer turned out to be the
  chat he already had: his messages queued only because a whole run was one long turn.
- **The climber became a loop of short ticks.** Each tick collects results, decides, submits the
  next Batch tasks, publishes, schedules its own wake-up and ends its turn. Chris's messages land
  between ticks as ordinary turns, with his authority and nothing to forge.
- **The change also fixed the reason for the stay-busy waits.** All long work already ran in Azure
  Batch, but results came back through local followers that died if the VM paused. Tasks now
  upload their output when they end, and every tick rebuilds its state from git and Batch.
- A unit test of the new cost tally caught a generator bug (a literal newline written into
  embedded Python) before it reached a run.

- **Short ticks, with long work handed off.** Chris's follow-up: make the turns short, or send
  long work to a sub-agent. Both went in. A tick has a budget of about 5 minutes. Benchmarks
  already ran in Azure Batch; the rest of the long local work (writing and gating a candidate,
  local benchmarks, profiling, ports, the morning report) now goes to background agents. The
  loop stays the dispatcher and the only writer of the record. An agent works on its own branch,
  can't spend money or merge, and its report is checked like a stranger's pull request.

### 10 October, 09:00: the log that stopped

- Chris noticed the page's log hadn't moved all morning. The run had logged its own start and
  then nothing for two and a half hours, while it decided five experiments. Every other part of
  the page was current, because tools kept those up to date; the log depended on the climber
  remembering to call `st.py event`.
- **Fix: the log writes itself.** On every publish, `tools/autolog.py` compares the last
  committed `status.json` with the new one and logs each new experiment, verdict, phase change,
  scoreboard move and run state change. A full, never-truncated copy goes to
  `results/hc/EVENTS.jsonl`, shown on the page as `log.html`.
- **The history was all there.** Every version of `status.json` is in git, so a backfill rebuilt
  229 events from 111 versions, including the 2.5 hours the run forgot to log. Keeping state in
  git paid for itself again.

### 10 October, 09:05: the machine goes public too

- Chris decided the machine is as much the story as the sieves. It gets its own public repo,
  MIT licence, with Primes as the worked example (`PUBLISH-PLAN.md`). The work splits the
  generic machine from a per-target adapter, so someone else can point it at their own hill.
- It ships after it has climbed on ticks at least once, from fresh history, after an audit
  against the public-repo rules.

### 10 October, 09:15: the bench, for anyone

- `tools/azure-setup.sh` stands up a Batch bench from nothing and `AZURE-BENCH.md` explains it.
  Two points for the write-up, from Chris. Batch runs pool nodes in its own subscriptions, so it
  reached Spot and VM sizes that our subscription's offer blocked outright. And the Spot quota
  needed a support request, which came back quickly.
- Chris's view: Azure Batch is one of the most underrated Azure services. For a machine like
  this it does three jobs at once: it reaches the hardware, it cleans up after itself on a
  deadline, and it keeps results safe while the climber sleeps.

### 10 October, 09:35: the climber's reasoning goes on the record

- The workshop can't see the climber's chat, only what it pushes. Results were all on record; the
  reasons behind each choice weren't, unless a commit message happened to carry them. That's the
  most interesting part of the trajectory for the write-up, and the hardest to rebuild later.
- The climber now records each decision with its reason, what it passed over and what it
  expects (`st.py decide`). The log flags any verdict made with no reasoning, so a lapse shows
  rather than relying on memory (lesson 2 again).

## Lessons so far

1. Controls in every round matter more than any optimisation. Without them, machine noise
   looks like progress or regression.
2. Anything that relies on the agent remembering to do it will lapse in a long run; put it in
   the tools it already calls. It lapsed twice: the heartbeat, then the log.
3. An unattended agent's authority must come from the person directly, never from a file it
   reads, however convenient the file is.
4. Write predictions down first. Most of them miss, and the misses are the information.
5. Separate the workshop from the climber. The climber is best when it doesn't decide what to
   climb or how the machine works.
6. To make an agent steerable, make its turns short. A long-running agent can't hear you;
   one that wakes, works and sleeps can. Long work still has to happen somewhere, so the agent
   you talk to dispatches it and never does it.
