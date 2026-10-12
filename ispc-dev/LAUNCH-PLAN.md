# Launch plan: public repos and the upstream PRs

Drafted 11 October, 11:30, while run ap-20261011T0100Z climbs the ports. Order matters: each step
gives the next something to link to. Owner in brackets: **C** is Chris, **W** the workshop.

## 0. Finish the climb: done 11 October

**Update, 12 October: the PR builds from `hc/ispc-landing-2` = 6cd85cd**, one commit on upstream
`drag-race` c4e42f00, with `PrimeISPC/solution_1` (wheel) and `PrimeISPC/solution_2` (base)
only. Both are byte-identical to `hc/ispc-final` (216629d). **solution_3 (the tables wheel) was
dropped on 12 October (Chris).** Upstream c4e42f00 (#1095) added a "Wheel algorithm" section to
CONTRIBUTING.md: primes known in advance must be the smallest primes, in order, all below 100;
patterns projected onto the sieve must be composed in code, not included as finished data.
solution_3's build-time tables break those rules; solution_1 complies (separate review,
12 October). `hc/ispc-final-tables` (57e0792) stays as a record only. The scoreboard below is
still the source for the PR numbers; ignore its solution_3 line. The READMEs' tables on
6cd85cd predate run 9 and need updating before the PR opens.

- [W] Done. Run ap-20261011T0645Z (run 9) ended 22:15 AEST, NZ$7.77, every pool deleted. The
  PR is built from two **branches** (the git proxy refuses tag pushes, so they aren't tags):
  `hc/ispc-final` = 216629d (solution_1 and solution_2) and `hc/ispc-final-tables` = 57e0792
  (the same plus solution_3; solutions 1 and 2 identical). Final per-thread scoreboard, 6 rounds,
  in `STATUS.md` (run 9 morning report): base vs mike-barber's Rust at 1T Zen 5 +10.2%, Zen 4
  (AVX-512) +8.2%, Zen 3 +6.7%, Cobalt −1.7%; wheel 3.3× (Zen 5), 2.9× (Zen 4), 3.0× (Zen 3),
  2.4× (Cobalt) the danielspaangberg C wheel; solution_3 +14% to +17% over solution_1. The
  4-thread lines are within half a point of 1T.
- [W] Zen 4 AVX-512 check done: the 16-lane loop lost 3% on Zen 4 and 7% on Intel, so it is gated
  on Zen 5 (family 1Ah); Zen 4 and Intel are now unchanged. Nothing for the README beyond one
  line on the gate.
- **Decided 11 October, 15:45 (Chris):**
  - **4-thread line: yes**, both entries. The climber builds `hc/line-4t` (a line at exactly 4
    threads, skipped on machines with 4 or fewer), self-tests and measures it, then merges it
    into `hc/champion` before the landing branch is rebuilt. README: one sentence on why.
  - **Zen 4 and Intel AVX-512 check of fold-1pc: yes, before the PR** (`D16as_v6`, `D16s_v5`).
    If it loses there, use the 16-lane loop on Zen 5 only, or say so in the README.
  - **Tables wheel: a third entry** (changed 16:30; **superseded 12 October: dropped**, see the
    update at the top of this step). `PrimeISPC/solution_3` from
    `hc/champion-tables`, with its own output label, tagged `faithful=yes` as
    `PrimeZig/solution_3` is. Its README says what is precomputed, that we're uneasy about it,
    and that `solution_1` is the wheel that computes everything itself; `solution_1`'s README
    points the other way. Words in `drafts/solution-3-notes.md`. Same PR as the other two, with
    an offer to drop it.
  - **Batch names in history: leave them now** and say so in the hill-climber README's security
    notes; retire the account (new account and group with neutral names, old ones deleted)
    after launch, when the next climb needs a quota request anyway (backlog).

## 1. The rules question goes with the PR, not before it

Decided 11 October, 12:10. An issue filed before any code is upstream asks about an entry that
doesn't exist yet and may sit unanswered; a grey-only PR mixes ISPC's language eligibility with
the rules question and turns a refusal into a "no" without reasons. So the issue
(`drafts/upstream-issue-F1-F2.md`) is filed on the day the clean ISPC PR opens, and the two link
to each other (step 4). Nothing grey goes in any PR until it's answered; if the answer is yes,
F1 or F2 arrives as a small follow-up PR to our own entry.

- [C] Optional: the PR 1094 comment (`drafts/pr-1094-comment.md`). Post it after our PR and the
  issue, or not at all.

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
  and nothing can be reached with them alone, but they break our own rule. Chris, 11 October: leave
  them for now (deleting branches is partial and breaks ledger links; rewriting breaks every
  link), and retire the account and group after launch.
- **56 commits carry a personal email address as author.** Already public; the PR commits will
  use the GitHub no-reply address.

## 4. The ISPC PR (day 2-3, after the repo is public)

- [W] Done 12 October: `hc/ispc-landing-2` = 6cd85cd, one squashed commit on upstream
  `drag-race` c4e42f00, authored with the GitHub no-reply address: `PrimeISPC/solution_1`
  (wheel) and `PrimeISPC/solution_2` (base) only, from `hc/ispc-final` (216629d), without the
  build outputs. solution_3 is out (step 0). Still to do on that branch: bring both READMEs'
  tables, output samples and summary percentages up to the run 9 scoreboard.
- [W] Check against CONTRIBUTING.md line by line:
  - Dockerfile builds from Ubuntu packages only (it does: `apt-get install ispc`); hadolint clean
    (hadolint 2.12.0 with `config/hadolint.yml`: no findings on either Dockerfile, 12 October);
  - wheel rules (#1095): solution_1 knows only 2, 3, 5, 7, 11 and 13 in advance, builds every
    pattern in code on each pass, and its tables only describe the wheel;
  - output tags honest: `algorithm=wheel` and `algorithm=base`, `faithful=yes`, `bits=1`;
  - **language eligibility**: ISPC is new to the repo. Give the evidence the rules ask for:
    Intel's open-source compiler since 2011, packaged in Debian and Ubuntu, used in Embree,
    OSPRay, Open Image Denoise and Unreal Engine;
  - READMEs state the rules notes plainly: small primes' single-bit ORs merged by the compiler
    (as in the Rust entry), dense clearing starting at the word holding p², the factor-3 set-up
    (hc-026);
  - every performance claim reproducible from the Dockerfile.
- [W] PR text from `PR-DESCRIPTION.md`, refreshed: what the entries are, the numbers against the
  fastest entry in each category per thread (the leaderboard's measure: one thread, and the
  4-thread line in the multi-thread table), and one line linking the climb map as "how it was
  built". The PR is about the code; the machine is a link, not the pitch. Name the real category
  leaders: for the wheel, danielspaangberg's `PrimeC/solution_2` (rogiervandam's `PrimeC/
  solution_5` extend is tagged `other`); for the base, Swift on the Threadripper and
  mike-barber's Rust elsewhere.
- [W] Cold read seeded with CONTRIBUTING.md, the README and two recent merged PRs, then a second.
  The issue gets its own cold read seeded with the PR text.
- [C] On the day, in this order:
  1. Open the PR. Its description carries a placeholder line: "Two questions about the base
     rules are in #N. Nothing in this PR depends on them."
  2. File the F1/F2 issue a few minutes later; its first line names the PR.
  3. Edit the PR description to fill in #N.
  All three before Dave's thread (step 6), so anyone clicking through finds the question
  already asked.

## 5. The ports (after the ISPC PR is in review)

**Before any port PR:** check the Zig and C++ wheel ports against the new wheel rules (#1095,
CONTRIBUTING.md "Wheel algorithm"), as solution_1 was: which primes are known in advance (the
smallest, in order, all below 100), and whether every projected pattern is composed in code
rather than included as finished data. The Zig tables wheel (138e074) is built like solution_3,
so expect it to fail the same way; check it first.

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
2. The PR open, linking the map, and the F1/F2 issue filed and cross-linked (step 4).
3. [C] Reply in Dave's thread: the teaser image, two lines, links to the PR and the map.
4. [C] A longer post: how the bench works, what the agents got wrong, what it cost. The map and
   `docs/how-it-works.md` are the source; a cold read before it goes out.
5. [C] Optional: Hacker News or a blog; the build log is the long read.

Keep the claims to what's measured and per-thread where it matters; the Arm gap and the grey
question go in plainly, not in footnotes.

## 7. After launch: OxCaml (Chris, 11 October)

A dedicated climb with the same bench (backlog 36; set-up plan in agentic-hill-climber
`examples/primes/next-climbs.md`): a faithful one-bit base sieve, then a wheel, against
gkpotter's `PrimeOCaml` entries and mike-barber's Rust, with the same sieve in plain OCaml as a
control. Before the run, Chris adds `opam.ocaml.org` to the climber environment's allowlist.
Upstream questions (`PrimeOCaml` or `PrimeOxCaml`; a hosted base image) go in an issue first.

cursed was shelved (Chris, 11 October 19:18): its compiler can't yet run a sieve (backlog 37).

