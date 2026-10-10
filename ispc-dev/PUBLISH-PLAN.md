# Publishing the machine

Decided 10 October: the hill-climbing machine gets its own public repo, `cauldnz/agentic-hill-climber`,
MIT licence, with the Primes entries as its worked example. The story is as much the machine as
the sieves. The upstream Primes PR stays solution-only and links to it as "how we did it", so
**v1 of the repo ships before the PR goes upstream** (Chris, 09:58).

v1 scope (Chris, 09:58):
- **The machine as it ran, cleaned.** No rewrite into a generic adapter interface; that's v2.
  Primes-specific scripts gather in `examples/primes/`, and the docs say plainly which parts are
  general and which are Primes.
- **Ticks, background agents and reasoning records go in after the dry run passes.** Until then
  the docs mark them as built but not yet run.

## What goes in

- **The machine, made generic.** The brief (`AUTOPILOT.md`), the protocol (`HILL-CLIMB.md`), the
  tick loop and background agents, the champion branch, interleaved rounds with an A/A floor and
  a rival, the acceptance rule, cost tally, the status page and the self-writing log.
- **An adapter per target.** Everything Primes-specific moves behind one interface: how to build,
  how to self-test, how to parse a result, which rivals to run and which machines decide.
  `examples/primes/` is the first adapter.
- **A bench anyone can stand up.** `tools/azure-setup.sh up` creates a resource group, storage,
  a Batch account and a service principal scoped to that group, checks the Spot quota and writes
  the env file; `rotate` issues a fresh short-lived secret per run; `check` proves the principal
  can't reach outside its group; `down` deletes it all. Nothing in the repo names a real account.
  `AZURE-BENCH.md` explains why Batch: it reaches VM sizes and Spot that a subscription's own
  offer may block, and a Spot quota needs a support request (ours was approved quickly).
- **The record.** `MACHINE-LOG.md` becomes the write-up, in Chris's house style. The ledger, the
  full event log and the retrospectives stay in the fork and are linked, with commit hashes.

## Before it goes public

1. The live run ends and `harness/ticks` merges; the tick dry run passes; at least one real climb
   runs on ticks. Publish a machine that has run, not a design.
2. Audit every file for section 7a of `AUTOPILOT.md`: no secrets, IDs, Azure resource or account
   names, or personal details. Resource names become environment variables.
3. Start the new repo with fresh history. Nothing from the fork's history comes across except
   by link.
4. Rebuild the fork's `dashboard` branch as an orphan (backlog item 13).

## Waiting on Chris

- Chris creates `cauldnz/agentic-hill-climber` empty; the workshop attaches it and does the
  extraction.
