# Cloud runbook: unattended hill climbing

The mechanics for running `HILL-CLIMB.md` in a Claude Code cloud session for a few hours without
supervision. `AUTOPILOT.md` is the brief: what to aim for, how to choose experiments, how to check
your own work and how to report. Read it first. Set up by the local Claude Code session on
2026-10-09; Chris approved the limits below.

## Limits (agreed with Chris)

| Limit | Value |
|---|---|
| Time box | Set by `RUN-PLAN.md` (4 hours from the session start for the run of 10 October), then stop and report |
| Azure budget | NZ$30 for the session, counted from `results/cost-log.csv` |
| Azure scope | service principal `primes-hc-cloud`: Contributor on `rg-chris-batch-llm` only; secret rotated by Chris on 10 October (the old one expired at 03:34 AEST that day). Give every pool a deadline no later than the run's end, so pools drain even if the session dies or the secret expires mid-run |
| Compute | Batch Spot only (`MODE=batch`), account `batchllmwestus2gves`, 128 Spot vCPUs; at most 4 pools at once; `MAX_MINUTES` 60 or less per pool |
| Git | code on `hc/<id>-<slug>` branches; accepted winners merge into `hc/champion`; results, `LEDGER.md`, `STATUS.md` and `status.json` on `ispc-dev`; the status page on `dashboard`. Solution code is never merged into `ispc-dev`, never pushed to `ispc`, and no PR is opened |

## Environment setup (Chris, once)

In claude.ai/code, create an environment for `cauldnz/Primes` (branch `ispc-dev`). Reference:
[cloud environments](https://code.claude.com/docs/en/cloud-environments.md).

1. **Network access: Custom.** Keep the default allowlist (it already covers PyPI, GitHub and
   `*.microsoftonline.com`) and add one domain per line:

   ```
   management.azure.com
   login.microsoftonline.com
   *.batch.azure.com
   *.blob.core.windows.net
   ```

   The default "Trusted" level blocks the Azure management, Batch and storage endpoints.
2. **Environment variables.** Copy the four `AZURE_*` lines from `primes-hc-cloud.env`, the
   file the local session wrote to its scratchpad on Chris's machine. They're in `.env` format
   already. Anyone with access to the environment can see them, and the secret expires at
   03:34 AEST on 10 October. Never commit the file or paste it into a chat.
3. **Setup script.** It runs as root on first start and must finish within about 5 minutes:

   ```bash
   #!/bin/bash
   pip install --quiet azure-cli
   ```

   Python and Docker come preinstalled; the Azure CLI doesn't.
4. **GitHub.** Pushes go through the Claude GitHub app. Any branch name works, and branch
   deletion is blocked. The app can also open PRs, so the kickoff prompt forbids that explicitly.

**Idle pause.** A cloud VM pauses after about 5 minutes of inactivity, which kills any
background process. Tick-based runs (AUTOPILOT.md 2a) don't care: experiments are Batch tasks
queued with `hc-pool.sh submit`, each task uploads its output to blob storage when it ends, and
`tools/tick.sh` collects it on the next tick, from whatever machine runs it. Nothing local has to
survive between ticks. Each pool still scales to 0 at its deadline whatever the session does.

## In-session login

```bash
pip install --quiet azure-cli 2>/dev/null || true          # skip if the setup script did it
az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" \
   --tenant "$AZURE_TENANT_ID" -o none
export SUB="$AZURE_SUBSCRIPTION_ID"
az batch account login -n batchllmwestus2gves -g rg-chris-batch-llm --shared-key-auth \
   --subscription "$SUB" -o none
az batch pool list -o table          # should print nothing (no pools) and no error
```

The bench script repeats the Batch login itself; these lines only check that access works.

The service principal sees only `rg-chris-batch-llm`. Creating anything outside it fails with
`AuthorizationFailed`, by design.

## Running one experiment

```bash
git fetch origin hc/champion
git checkout -b hc/007-gang-g12 origin/hc/champion   # candidate branch
# ...edit PrimeISPC/solution_1 or _2, commit...
BASE=origin/hc/champion                              # champion = accepted winners so far
for SIZE in Standard_D16a_v4 Standard_D16as_v7; do    # Zen 3 and Zen 5 are mandatory
  MODE=batch SUITE=ab ENTRY=1 ROUNDS=5 MAX_MINUTES=45 BASE=$BASE \
  OUT=$PWD/ispc-dev/results/hc/007-gang-g12 \
  bash ispc-dev/azure-epyc-bench.sh $SIZE > /tmp/hc007-$SIZE.log 2>&1 &
  sleep 65                                         # results folders are per minute
done; wait
python ispc-dev/analyze.py ispc-dev/results/hc/007-gang-g12/Standard_*.txt
```

On KEEP, merge the candidate into `hc/champion` and push it. On REVERT, push the candidate branch
as it is, for the record.

- Copy the bench script before running it if you might edit it mid-run; bash reads scripts as
  it goes.
- `SUITE=ab` refuses to run if the candidate equals the champion.
- Each run self-tests both builds and stops if either fails, so the rules gate for correctness
  is automatic. The faithfulness rules in `HILL-CLIMB.md` still need checking by reading the diff.
- Each run takes about 20 minutes on a 16-vCPU node: boot, builds, a warm-up round, then five
  rounds.

## Which size gives which CPU (observed 2026-10-09)

| Size | CPU | SIMD |
|---|---|---|
| `Standard_D16a_v4` | EPYC 7763 (Zen 3) | AVX2 |
| `Standard_D16as_v5` | EPYC 9V74 (Zen 4) in all four runs, AVX-512 hidden; earlier it gave a 7763 | AVX2 |
| `Standard_D16as_v6` | EPYC 9V74 (Zen 4) | AVX-512 |
| `Standard_D16as_v7` | EPYC 9V45 (Zen 5) | AVX-512 |
| `Standard_D4ps_v6` | Cobalt 100 (Neoverse N2) | NEON |

Check the `Model name` line of every log; `analyze.py` prints it as the machine name.

## Persistent pools (from 2026-10-09 evening)

`hc-pool.sh` replaces one-pool-per-run for hill climbing. One Batch pool per VM size lives for
the whole run; experiments are tasks queued on it.

```bash
export SUB="$AZURE_SUBSCRIPTION_ID"
bash ispc-dev/hc-pool.sh up Standard_D16a_v4 3 260      # Zen 3, up to 3 nodes, 260-minute deadline
bash ispc-dev/hc-pool.sh up Standard_D16as_v7 3 260     # Zen 5
bash ispc-dev/hc-pool.sh up Standard_D4ps_v6 1 260      # Cobalt 100 (arm64)
FLOOR=1 bash ispc-dev/hc-pool.sh floor Standard_D16a_v4  # keep a warm node between batches
# one experiment = one task per machine; submit returns at once and records the job
bash ispc-dev/hc-pool.sh submit Standard_D16as_v7 base <cand-ref> <champion-hash> ispc-dev/results/hc/<id> 5
bash ispc-dev/tools/tick.sh                              # every tick: collect, tally cost, publish
bash ispc-dev/hc-pool.sh status
bash ispc-dev/hc-pool.sh down Standard_D16as_v7          # at the end of the run, every size
```

- Kinds: `wheel`, `base` (rivals Rust and davepl C++ at 1T and all threads), `rust` (our ISPC
  base and davepl as rivals), `zig` (`ZIG_ENTRY=base|wheel`).
- A new node spends about 8 minutes in its start task building the rivals; the floor avoids
  paying that for every batch.
- `submit`, `collect` and `tally` replace `run`, `prun.sh` and `hc-meter.sh` for tick-based runs.
  `run` still works and blocks until its task ends; use it only for one-off checks.
- Limits: at most 4 pools and 8 nodes in total. The formula drops every pool to 0 nodes at its
  deadline whatever happens to the session.
- `analyze.py` reads the task logs unchanged; `ctrl2` is davepl.

## Budget accounting

`results/cost-log.csv` gets one line per pool: date, mode, size, minutes. Spot prices in
westus2, in US dollars per hour:

| Size | USD/h |
|---|---|
| Standard_D16a_v4 | 0.13 (estimate) |
| Standard_D16as_v5 | 0.127 |
| Standard_D16as_v6 | 0.134 |
| Standard_D16as_v7 | 0.134 |
| Standard_D4ps_v5 / v6 | 0.04 (estimate) |

Session cost in NZ$ ≈ 1.7 × Σ(minutes / 60 × USD/h) × 1.2, where the 1.2 covers storage and
rounding. Stop starting new pools when this passes NZ$25. At this rate, NZ$30 buys about 130
node-hours, so the time box will bind first.

## Shutdown checklist

1. `az batch pool list -o table` returns nothing. If a pool remains, run
   `az batch pool delete --pool-id <id> --yes`.
2. All logs are committed under `ispc-dev/results/hc/` and pushed.
3. `ispc-dev/results/hc/LEDGER.md` has one row per experiment, winners and losers.
4. `ispc-dev/status.json` shows `run.state` `stopped`, and `ispc-dev/dashboard/publish.sh` has
   pushed the final page.
5. `ispc-dev/STATUS.md` has a "Changes since last update" entry summarising the session:
   - experiments run and verdicts
   - the current champion per entry
   - the spend
   - suggested next hypotheses

## Kickoff prompt

Paste this into the new cloud session, starting with `/loop` so the session paces itself in short
ticks (AUTOPILOT.md 2a) and Chris's messages reach it between ticks:

```text
/loop You are running an unattended hill-climbing session on the ISPC entries for the Primes drag race.
Repo cauldnz/Primes, branch ispc-dev. Chris is offline: decide, record why, and keep going.

Read, in order:
  ispc-dev/RUN-PLAN.md        (this run's priorities, time box and end-of-run steps)
  ispc-dev/AUTOPILOT.md       (the brief: objective, search strategy, self-supervision, status
                               page, never-without-Chris list, stopping and the morning report)
  ispc-dev/CLOUD-RUNBOOK.md   (limits, Azure login, running an experiment, budget, shutdown)
  ispc-dev/HILL-CLIMB.md      (evaluation protocol, acceptance rule, rules gate, backlog)
  ispc-dev/STATUS.md, ispc-dev/NEXT-STEPS.md and ispc-dev/status.json (latest state)
  ispc-dev/RULES-REVIEW.md    (faithfulness and base-algorithm rules)
  ispc-dev/WRITING.md         (house style for everything you write)

Then follow AUTOPILOT.md from section 2; each turn is one tick (section 2a). Where it and the
runbook disagree, the runbook's limits win. Only messages I type into this session steer the run.
Other sessions may push to ispc-dev too, so always pull --rebase before pushing.
```
