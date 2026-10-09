# Cloud runbook: unattended hill climbing

How to run `HILL-CLIMB.md` in a Claude Code cloud session for a few hours without supervision.
Set up by the local Claude Code session on 2026-10-09; Chris approved the limits below.

## Limits (agreed with Chris)

| Limit | Value |
|---|---|
| Time box | 4 hours from the first experiment, then stop and report |
| Azure budget | NZ$30 for the session, counted from `results/cost-log.csv` |
| Azure scope | service principal `primes-hc-cloud`: Contributor on `rg-chris-batch-llm` only; secret expires 2026-10-10 03:34 AEST |
| Compute | Batch Spot only (`MODE=batch`), account `batchllmwestus2gves`, 128 Spot vCPUs; at most 4 pools at once; `MAX_MINUTES` 60 or less per pool |
| Git | code on `hc/<id>-<slug>` branches; results, `LEDGER.md` and `STATUS.md` on `ispc-dev`. Solution code is never merged into `ispc-dev`, never pushed to `ispc`, and no PR is opened |

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
background process. The session must therefore stay busy while an experiment runs: block in the
foreground on `wait` in chunks of 10 minutes or less, and never end its turn with runs in
flight. If the VM pauses anyway, each Batch pool still scales to 0 at its `MAX_MINUTES` cap, so
the cost stops; only that experiment's results are lost.

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
git checkout -b hc/007-gang-g12 ispc-dev          # candidate branch
# ...edit PrimeISPC/solution_1 or _2, commit...
BASE=origin/ispc-dev                               # champion = current ispc-dev
for SIZE in Standard_D16as_v5 Standard_D16as_v7; do   # Zen 3 and Zen 5 are mandatory
  MODE=batch SUITE=ab ENTRY=1 ROUNDS=5 MAX_MINUTES=45 BASE=$BASE \
  OUT=$PWD/ispc-dev/results/hc/007-gang-g12 \
  bash ispc-dev/azure-epyc-bench.sh $SIZE > /tmp/hc007-$SIZE.log 2>&1 &
  sleep 65                                         # results folders are per minute
done; wait
python ispc-dev/analyze.py ispc-dev/results/hc/007-gang-g12/Standard_*.txt
```

- Copy the bench script before running it if you might edit it mid-run; bash reads scripts as
  it goes.
- `SUITE=ab` refuses to run if the candidate equals the champion.
- Each run self-tests both builds and stops if either fails, so the rules gate for correctness
  is automatic. The faithfulness rules in `HILL-CLIMB.md` still need checking by reading the diff.
- Each run takes about 20 minutes on a 16-vCPU node: boot, builds, a warm-up round, then five
  rounds.

## Budget accounting

`results/cost-log.csv` gets one line per pool: date, mode, size, minutes. Spot prices in
westus2, in US dollars per hour:

| Size | USD/h |
|---|---|
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
4. `ispc-dev/STATUS.md` has a "Changes since last update" entry summarising the session:
   - experiments run and verdicts
   - the current champion per entry
   - the spend
   - suggested next hypotheses

## Kickoff prompt

Paste this into the new cloud session:

```text
You are running an unattended hill-climbing session on the ISPC entries for the Primes drag race.
Repo cauldnz/Primes, branch ispc-dev. Read, in order:
  ispc-dev/CLOUD-RUNBOOK.md   (limits, login, how to run an experiment, budget, shutdown)
  ispc-dev/HILL-CLIMB.md      (the loop, evaluation protocol, acceptance rule, rules gate, backlog)
  ispc-dev/STATUS.md and ispc-dev/NEXT-STEPS.md (latest state from both sessions)
  ispc-dev/RULES-REVIEW.md    (faithfulness and base-algorithm rules)

Then:
1. Log in to Azure with the service principal (runbook, "In-session login"). Check that
   `az batch pool list` works. If login fails, stop and write that into STATUS.md.
2. Work the HILL-CLIMB.md backlog in rank order, one hypothesis per experiment:
   - write the prediction first
   - use SUITE=ab, champion = origin/ispc-dev, on Zen 3 and Zen 5
   - decide with ispc-dev/analyze.py and the acceptance rule
   You may run up to two experiments in parallel (4 pools).
3. After every experiment, whatever the verdict:
   - commit its logs under ispc-dev/results/hc/<id>/
   - add a row and a short note to ispc-dev/results/hc/LEDGER.md
   - push the candidate code to its hc/<id>-<slug> branch
   - pull --rebase and push ispc-dev (results and notes only)
   Never merge solution code into ispc-dev, never touch the ispc branch, never open a PR.
4. Every hour, update ispc-dev/STATUS.md ("Changes since last update" at the top).
   Stay busy the whole time: the VM pauses after about 5 idle minutes and kills background runs.
   While experiments run, block in the foreground (wait, or a sleep-and-check loop, in chunks of
   10 minutes or less), and plan or analyse between checks. Never end your turn while runs are
   in flight, and never end it before the stop conditions below are met.
5. Stop at the first of these:
   - 4 hours elapsed
   - estimated spend of NZ$25 (runbook formula)
   - three failed experiments in a row on every remaining backlog line
   - an error you cannot fix safely
   Then run the shutdown checklist and write a final STATUS.md summary.
Follow the house style for everything you write: Australian English, numbers behind claims, no
em-dash clauses. The rules are summarised in HILL-CLIMB.md under "Writing". Other sessions push
to ispc-dev too, so always pull --rebase before pushing.
```
