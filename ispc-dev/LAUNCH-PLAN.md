# Launch plan: public repos and the upstream PRs

Drafted 11 October, 11:30, while run ap-20261011T0100Z climbs the ports. Order matters: each step
gives the next something to link to. Owner in brackets: **C** is Chris, **W** the workshop.

## 0. Finish the climb (today)

- [W] Run ap-20261011T0100Z ends about 15:00 AEST. Review the morning report; freeze the
  numbers we'll quote: `hc/ispc-ref`, the per-thread table, the port tables.
- [C] Decide the 4-thread line (the per-thread ranking). If yes, the climber merges `hc/line-4t`
  into `hc/champion` before the landing branch is rebuilt.

## 1. Ask the rules question (day 1)

- [C] File the F1/F2 issue upstream (`drafts/upstream-issue-F1-F2.md`, two cold reads done).
  Nothing grey goes in any PR until it's answered; the PRs stand on the clean champion.
- [C] Optional: the PR 1094 comment (`drafts/pr-1094-comment.md`). Post it after the issue, or
  not at all.

## 2. The hill-climber repo goes public (day 1-2)

- [W] Finish the record: label every experiment by kind (novel, borrowed, tuning, permitted) and
  tier; rebuild the climb map with the ports run; write `docs/generalising.md` from that run;
  refresh the README numbers, per-thread figures included.
- [W] A cold read of the README and the climb map, seeded with nothing (`READER-REVIEW.md`),
  then a second after the fixes.
- [W] Audit the repo's full history for secrets, IDs, account and resource names, personal
  details. (Checked 11 October: none.)
- [C] Make `cauldnz/agentic-hill-climber` public; switch on GitHub Pages (main, `/docs`). Check
  the map, the docs and every link on the live site.

## 3. The fork: what's public already

`cauldnz/Primes` is public, history included. Checked 11 October:
- **No keys, secrets, subscription or tenant IDs** in any of our commits.
- **The Batch account and resource group names are in old history** (29 and 22 mentions, mostly
  on early `hc/*` branches and in `ispc-dev` before the 10 October clean-up). They aren't secrets,
  and nothing can be reached with them alone, but they break our own rule. Options: leave them
  (they've been public since 9 October); delete the old `hc/0xx` branches that carry them
  (keeping their code reachable through the ledger's commit hashes); or rewrite history. I'd
  delete the branches and leave `ispc-dev` history alone. [C] to choose.
- **56 commits carry a personal email address as author.** Already public; the PR commits will
  use the GitHub no-reply address.

## 4. The ISPC PR (day 2-3, after the repo is public)

- [W] Rebuild `hc/ispc-landing` on the upstream `drag-race` branch from the clean champion (plus
  `hc/line-4t` if chosen): `PrimeISPC/solution_1` (wheel) and `PrimeISPC/solution_2` (base) only.
  One squashed commit, authored with the GitHub no-reply address.
- [W] Check against CONTRIBUTING.md line by line:
  - Dockerfile builds from Ubuntu packages only (it does: `apt-get install ispc`); hadolint clean;
  - output tags honest: `algorithm=wheel` and `algorithm=base`, `faithful=yes`, `bits=1`;
  - **language eligibility**: ISPC is new to the repo. Give the evidence the rules ask for:
    Intel's open-source compiler since 2011, packaged in Debian and Ubuntu, used in Embree,
    OSPRay, Open Image Denoise and Unreal Engine;
  - READMEs state the rules notes plainly: small primes' single-bit ORs merged by the compiler
    (as in the Rust entry), dense clearing starting at the word holding p², the factor-3 set-up
    (hc-026);
  - every performance claim reproducible from the Dockerfile.
- [W] PR text from `PR-DESCRIPTION.md`, refreshed: what the entries are, the numbers against the
  fastest entry in each category per thread and total, and one line linking the climb map as
  "how it was built". The PR is about the code; the machine is a link, not the pitch.
- [W] Cold read seeded with CONTRIBUTING.md, the README and two recent merged PRs, then a second.
- [C] Open the PR.

## 5. The ports (after the ISPC PR is in review)

From this run's results, one PR each, each with its own cold read:
- **Zig** (`PrimeZig`, both designs): check the next free solution number against open PRs
  (PR 1094 took 5 after starting as 4).
- **C++ wheel**: new ground, no C++ wheel exists.
- **C++ base**: same characteristics as davepl's `solution_5`, and about 40% faster. CONTRIBUTING
  asks that this be offered to the existing author first. [C] to decide: a PR to his solution,
  or a new one with the reason given.
- **Rust**: only if this run closes the gap to mike-barber's entry; otherwise no PR.

## 6. The pop

On the day the ISPC PR opens, in this order:
1. The climb map live and public, README current.
2. The PR open, linking the map.
3. [C] Reply in Dave's thread: the teaser image, two lines, links to the PR and the map.
4. [C] A longer post: how the bench works, what the agents got wrong, what it cost. The map and
   `docs/how-it-works.md` are the source; a cold read before it goes out.
5. [C] Optional: Hacker News or a blog; the build log is the long read.

Keep the claims to what's measured and per-thread where it matters; the Arm gap and the grey
question go in plainly, not in footnotes.
