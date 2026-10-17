# fai-002: the Fai base on Azure, an A/A baseline

The candidate is `hc/fai-002-baseline` (2a2fae9), the champion `hc/fai-champion` (1ce921d)
with a README comment added, so the two binaries are identical. One task per machine, 6 counted
rounds, all labels run in the same rounds. The controls are our plain OCaml base
(`hc/ocaml-final`, solution_4), mike-barber's Rust and our ISPC base (`hc/ispc-landing-4`,
solution_2). The CPU model line was checked in every log.

The task also showed that the `fai` bench kind works. Fai installs from its release inside the
Dockerfile on x86-64 and arm64 nodes, and the solution builds in 37-42 s. Both self-tests passed
13/13.

## Results

Passes in 5 s, median of 6 rounds.

| | Zen 5 1T | Zen 5 4T | Zen 3 1T | Zen 3 4T | Cobalt 1T | Cobalt 4T |
|---|---:|---:|---:|---:|---:|---:|
| Fai base | 1.8k | 7.2k | 0.9k | 3.7k | 1.2k | 4.7k |
| plain OCaml base | 30.4k | 117.5k | 16.9k | 66.2k | 3.4k | 13.0k |
| mike-barber Rust | 118.8k | 460.5k | 52.6k | 210.2k | 42.9k | 171.3k |
| our ISPC base | 129.9k | 504.2k | 56.0k | 223.5k | 42.1k | 168.1k |

Notes on the results:
- **Noise floor.** The 95% intervals on the A/A pair are ±1.2% at 1T on Zen 5, ±1.8% on Zen 3
  and ±0.1% on Cobalt.
- **Against plain OCaml.** The plain Fai loop gets 1/17 of plain OCaml's passes per thread on
  Zen 5 and 1/19 on Zen 3, but 1/2.8 on Cobalt. On Cobalt OCaml pays a `dmb ishld` barrier on
  every 64-bit store (run 10).
- **Scaling.** Fai keeps its per-thread speed at 4T on all three machines.
