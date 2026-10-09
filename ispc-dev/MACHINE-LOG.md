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

## Lessons so far

1. Controls in every round matter more than any optimisation. Without them, machine noise
   looks like progress or regression.
2. Anything that relies on the agent remembering to do it will lapse in a long run; put it in
   the tools it already calls.
3. An unattended agent's authority must come from the person directly, never from a file it
   reads, however convenient the file is.
4. Write predictions down first. Most of them miss, and the misses are the information.
5. Separate the workshop from the climber. The climber is best when it doesn't decide what to
   climb or how the machine works.
