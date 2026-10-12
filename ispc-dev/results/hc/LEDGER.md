# Hill-climbing ledger

| id | date | entry | hypothesis | prediction | Zen 3 1T/16T (median, Δ) | Zen 5 1T/16T (median, Δ) | verdict | commit |
|---|---|---|---|---|---|---|---|---|
| 001 | 2026-10-09 | both | Profile first: where do the cycles go, ours against C5 and Rust? | Base gap sits mostly in the dense phase (local Xeon: dense 128k cycles a pass against Rust's 82k) | Zen 4 (D16as_v5 landed on a 9V74): base dense 114k / sparse 143k / scan 5k cycles a pass, Rust 79k / 135k / 6k | Zen 5: see note | measurement | `3b02d14` (harness) |
| 002 | 2026-10-09 | base | Vector dense resets: one single-bit OR per composite, per SIMD lane, folded by LLVM into constant vector ORs, as the SLP vectoriser does for Rust | +10% to +18% at 1T on Zen, similar at all threads | Zen 3 (7763, confirm run): 57.2k / 416.9k, +21.9% / +21.8%, 5/5; Zen 4 (v5): +22.9% / +28.1%, 4/4 | Zen 5: 107.6k / 888.3k, +23.5% / +29.0%, 5/5; confirm run +23.8% / +29.7%, 4/4 | KEEP, confirmed on fresh nodes, merged | `4d35020` on `hc/champion` |
| 003 | 2026-10-09 | base | Pointer walk over sparse chunks: 11 instructions per eight ORs instead of 27 | Zen 5 1T +4% to +8% (sparse gap 15k cycles), Zen 4 +0% to +3% | Zen 4 (v5): 51.3k / 416.6k, +3.6% / +7.8%, 5/5, A/A ±0.5% | Zen 5: 97.8k / 696.3k, +12.3% / +1.3%, 5/5, A/A ±0.9% | KEEP, merged | `cacfd8f` on `hc/champion` |
| 004 | 2026-10-09 | wheel | A lone prime (13) skips the fused group loop | +1% to +3% 1T (13 costs ~9k cycles a pass); local Xeon +0.4% to +5.8% | Zen 3 (7763): 87.5k / 729.8k, +8.7% / +3.9%, 5/5; A/A at 1T −3.4% to +14.5% (one outlier round) | Zen 5: 158.3k / 1.30M, +4.9% / +5.1%, 5/5, A/A within 1.9% | KEEP, merged | `hc/champion` |
| 005 | 2026-10-09 | wheel | No masked stores: apply_group unmasked, partial vectors run into padding | +3% to +6% on the AVX2 path, +1% to +3% with AVX-512; local Xeon +2% to +19% | Zen 3 (7763): 87.3k / 732.1k, +4.5% / +4.1%, 4/5 at 1T, 5/5 at 16T; A/A at 1T −2.6% to +4.6% | Zen 5: 146.9k / 1.22M, −1.7% / −0.9%, 0/4 | REVERT (Zen 5 −1.7% at 1T) | `hc/005-wheel-unmasked-tails` |
| 006 | 2026-10-09 | wheel | Build with `--addressing=64`: ISPC sign-extends 32-bit offsets on every strided OR, and the sparse loop spills | +3% to +6% 1T on Zen; local Xeon +4% to +8% | Zen 3 (7763): +3.1% / +4.1%, but the node was noisy (C5 control 36k–59k, A/A up to +31%): inconclusive | Zen 5: 154.0k / 1.28M, +4.0% / +3.4%, 5/5, control within 3% | Zen 3 rerun as 006b against the new champion | `hc/006-wheel-addr64` |

## Notes

**001, profile.** Azure D-series nodes expose no hardware PMU counters, so perf fell back to
`cpu-clock` sampling, and the phase split came from TSC timers built into copies of our base
entry and the Rust entry. Dense was 60–70% of the base gap to Rust and sparse 15–30%. Next:
vectorise dense.

**002, vector dense.** The prediction (+10% to +18%) was too cautious: +22% to +24% at 1T on
Zen 3, 4 and 5, and +22% to +30% at all threads. Over 20%, so it was confirmed on fresh nodes
with clean builds, and the rules re-read: each composite has its own single-bit OR in the
source, in the lane holding its word, and LLVM merges them, as it does for the Rust entry. The
base entry now beats Rust at 1T on Zen 3 (+3.1%) and Zen 4 (+2.4%) and trails by 15% on Zen 5.
Vector resets past factor 128 blow up ISPC compile times (over 7 minutes for one target), so
a higher dense limit is parked. `avx2-i32x16` and `avx512skx-x16` fail to fold the masks.

**003, sparse pointer walk.** Zen 5 +12.3% at 1T against a 4–8% prediction: on Zen 5 the
sparse loop was bound by instruction count, not stores. Zen 4 gained 3.6% at 1T and 7.8% at
16T. The local Xeon showed nothing, which is a warning about ranking changes there.

**005, wheel unmasked stores.** Zen 3 gained 4% to 6%; Zen 5 lost 1.7% at 1T with a noisy A/A.
On AVX-512 masked stores are cheap, so the padding and overrun only add work there. Next: keep
the change for AVX2 targets only, which can't move Zen 5. That can't pass the "both machines"
rule by construction, so it needs Chris's call if it wins on Zen 3.
| 007 | 2026-10-09 | wheel | hc-005 for SSE and AVX2 targets only (Zen 3 run against `4d35020`; the Zen 4 run was stopped because it started after hc-004 merged, then rerun as 007-r on the rebased branch); AVX-512 code byte-identical to the champion | Zen 3 and AVX2-only Zen 4 +3% to +5%; Zen 5 exactly 0 | Zen 3 (7763, vs `4d35020`): 84.4k / 729.9k, +3.7% / +4.4%, 4/5 at 1T, 5/5 at 16T, A/A within 2.8% | AVX2-only Zen 4 (9V74, rebased, vs `0175d18`): 82.3k / 696.4k, +5.3% / +3.8%, 5/5; Zen 5 code byte-identical | Chris to decide: recommend KEEP (gains on every AVX2 machine, no change with AVX-512) | `hc/007-wheel-unmasked-avx2` |
| 008 | 2026-10-09 | wheel | Copy the 7·11 tile by doubling with memcpy; the foreach copy compiled to scalar moves | +1% to +3% 1T on Zen; local Xeon inconclusive (2 of 4) | Zen 3 run stopped after two rounds once Zen 5 came back flat | Zen 5: 149.9k / 1.29M, +0.1% / −0.1%, 3/5 | REVERT (no gain) | `hc/008-wheel-tile-memcpy` |

**004, lone prime.** Predicted +1% to +3%, measured +4% to +9%. The research agent's phase
count (13 costs 70% of a full group) was right; my prediction discounted it.

**Harness fix, 17:50 AEST.** A run takes its champion from `origin/hc/champion` when it starts.
The first hc-007 Zen 4 run started 17 seconds after hc-004 merged, so it would have compared a
candidate without hc-004 against a champion with it. I stopped it before any round ran. From
now on each candidate is merged with the current champion first and `BASE` is pinned to a
commit hash.
| 009 | 2026-10-09 | base | Next-prime scan a word at a time with count-trailing-zeros | +1% to +3% 1T (scan is 2–4% of a pass) | Zen 3 (7763): 55.5k / 427.3k, −0.3% / −0.3%, 0/2, stopped after 3 rounds | Zen 5: 121.6k / 979.1k, −1.4% / −1.2%, 0/1, stopped | REVERT | `hc/009-base-scan-ctz` |
| 006b | 2026-10-09 | wheel | hc-006 rerun on Zen 3 against champion `0175d18` | as 006 | Zen 3 (7763): 87.1k / 754.0k, +1.9% / +3.5%, 4/5 at 1T, 5/5 at 16T, control within 1.1% | Zen 5 from 006: +4.0% / +3.4%, 5/5 | KEEP, merged | `hc/champion` |

**006, 64-bit addressing.** One build flag: +2% to +4% on Zen 3 and Zen 5. Useless for the base
entry, whose sparse loop already walks a pointer.

**007, unmasked stores on AVX2 only.** +3.7% / +4.4% on Zen 3 and +5.3% / +3.8% on AVX2-only
Zen 4; the AVX-512 code is byte-identical, so Zen 5 can't move. The acceptance rule asks for
2% on Zen 5 as well, so this waits for Chris rather than merging. It matters for runner 74,
which is AVX2-only.

**008, tile memcpy.** No gain on Zen 5. The copy is too small a share of the pass to matter.
| 011 | 2026-10-09 | wheel | Fusion group size G = 6 instead of 8 | +2% to +5% 1T; local Xeon medians G=6 +5% over G=8 (noisy) | Zen 3 (7763): 86.7k / 771.4k, −1.2% / +2.8%, 1/5 at 1T, 5/5 at 16T | Zen 5: 167.0k / 1.34M, +4.5% / −0.3%, 5/5 at 1T; +6.2% at 4T, +6.3% at 8T | REVERT (Zen 3 −1.2% at 1T) | `hc/011-wheel-g6` |
| 010 | 2026-10-09 | both | Re-profile both champions on Zen 5 | Base gap to Rust mostly gone | n/a | Zen 5: base and Rust both 38k dense, 61k sparse, 4k scan per pass; wheel perf: sparse (in run_sieve) 52%, groups 35%, tile and 13 12% | measurement | `7360392` |
| 012 | 2026-10-09 | wheel | 64-bit bit indices in the wheel sparse loop (no sign extension per OR) | +2% to +5% 1T; local Xeon +0.5% to +8%, 4/4 | Zen 3 (7763): 92.1k / 785.2k, +5.2% / +4.2%, 5/5 | Zen 5: 169.8k / 1.31M, +4.8% / −2.1%, 5/5 at 1T, 0/5 at 16T | REVERT (Zen 5 −2.1% at 16T) | `hc/012-wheel-sparse-i64` |

**009, base word scan.** Slightly slower on both machines (−0.3% Zen 3, −1.4% Zen 5). The bit
scan is already cheap; the extra branches cost more than they save. Stopped early.

**010, re-profile.** On Zen 5 the base entry now matches Rust phase for phase (dense 38k,
sparse 61k, scan 4k cycles a pass). The uninstrumented base runs 123k–125k passes against
Rust's 125k at 1T. On the wheel, the sparse loop is the largest phase at 52% of samples.
| 013 | 2026-10-09 | base | Add the avx512skx-x8 target now that dense resets are vectorised | Zen 5 +2% to +5% (dense is 35% of a pass); no change without AVX-512 | n/a (no AVX-512 on Zen 3) | Zen 5: 125.8k / 993.9k, +1.0% / +0.6%, 5/5, A/A within 0.3% | Chris to decide: small but consistent, AVX-512 only | `hc/013-base-avx512` |
| 014 | 2026-10-09 | wheel | G = 6 with AVX-512 only, 8 otherwise | Zen 5 as hc-011, Zen 3 unchanged | identical code to champion | Zen 5 as hc-011: +4.5% / −0.3%, +6% at 4T and 8T; Zen 4 AVX-512 (D16as_v6, 9V74): 109.8k / 906.5k, +4.3% / +0.9%, 5/5 | Chris to decide: recommend KEEP | `hc/014-wheel-g6-avx512` |

**011 and 014, group size.** G = 6 helps the AVX-512 build on Zen 5 and hurts the AVX2 build
on Zen 3 at 1T. hc-014 picks G per target; its AVX-512 code is byte-identical to hc-011's and
its AVX2 code to the champion's, so hc-011's numbers stand for it. Like hc-007 it can't pass
the "2% on both Zen 3 and Zen 5" rule by construction.
| 015 | 2026-10-09 | wheel | hc-012 without the register spill: loop bounded on stream 0, no reloads | Zen 3 and Zen 5 +4% to +5% 1T, 16T no longer negative | Zen 3 (7763): 92.7k / 790.0k, +5.8% / +5.0%, 5/5 | Zen 5: 173.9k / 1.43M, +6.9% / +6.8%, 5/5 | KEEP, merged | `hc/champion` |

**012 and 015, wheel sparse indices.** 64-bit indices gained about 5% at 1T on both machines,
but the loop spilled and reloaded its base pointer before every OR, and Zen 5 lost 2.1% at 16T,
where two threads share a core's load ports. hc-015 frees one register and removes the reloads.
| 016 | 2026-10-09 | wheel | No lead-ins: all group members start at the earliest start word; own bits cleared afterwards | +3% to +8% 1T; local Xeon 3/4 | Zen 3 (7763): 92.9k / 791.8k, +5.1% / +5.4%, 5/5 | Zen 5: 166.8k / 1.38M, +2.6% / +2.6%, 4/4 | KEEP, merged on top of hc-015; counts re-checked | `hc/champion` |

**015, the spill fixed.** Freeing one register turned hc-012's −2.1% at 16T on Zen 5 into
+6.8%, and lifted 1T too (+6.9%). The 16T loss had been the reloads, as suspected.
| 017 | 2026-10-09 | wheel | Dense threshold 160 instead of 256, now that sparse is cheaper | ±2%; local Xeon medians favour 160 by 6% (noisy) | Zen 3 (7763): −1.2% / −1.8%, 0/3 at 16T, stopped after 3 rounds | Zen 5: −0.7% / −0.0%, stopped | REVERT; 256 stays | `hc/017-wheel-dense160` |
| 018 | 2026-10-09 | base | Sparse loop clears two chunks a trip | 0% to +3% on Zen 5; nothing on the sandbox earlier | Zen 3: +0.5% / +0.2% after 2 rounds, stopped | Zen 5: 119.5k / 982.8k, +0.8% / −0.8%, noisy node (A/A to −3.6%) | REVERT | `hc/018-base-sparse-x2` |

**016, no lead-ins.** +5% on Zen 3 and +2.6% on Zen 5, at every thread count. The fused loop now
starts all members together, which also removed most of the masked stores that hc-007 targets
on AVX2; hc-007's remaining value needs a fresh measurement on top of this.
| 019 | 2026-10-09 | wheel | hc-007 and hc-014 together on top of the current champion (`64e94aa`), for Chris | Zen 3 +2% to +4%; Zen 5 +3% to +5% | Zen 3 (7763): 99.6k / 850.4k, +1.1% / +2.3%, 4/5 at 1T, 5/5 at 16T | Zen 5: 189.4k / 1.46M, +6.4% / +1.6%, 5/5 at 1T; +8.4% at 4T, +7.1% at 8T | Passes the acceptance rule as one change; not merged because hc-007 and hc-014 were not each accepted on their own. Chris to decide: recommend merging | `hc/champion-plus-target-specific-2` |

**018, base sparse unrolled by two.** Flat on a noisy Zen 5 node and on Zen 3. With hc-009 and
hc-013 this closes the obvious base levers: it now matches Rust phase for phase on Zen 5.

**019, the target-specific pair.** On today's champion, hc-007 and hc-014 together give Zen 3
+1.1% / +2.3% and Zen 5 +6.4% / +1.6%, with +7% to +8% at 4 and 8 threads on Zen 5. That
passes the acceptance rule, but the brief says to combine winners only after each passes on its
own, so the branch waits for Chris.
| 020 | 2026-10-09 | base | Keep the scalar dense routine on NEON (regression fix) | Cobalt 100 back to at least the start of the run; x86 code identical | n/a (identical x86 code) | n/a (identical x86 code); Cobalt 100: 41.1k / 164.0k (4T), +64.2% against the champion, level with the start (−0.0% / +0.2%), 5/5 | KEEP, merged as a regression fix | `hc/champion` |

**Protocol miss: arm64.** HILL-CLIMB asks for an arm64 run on any change to shared code. I
didn't run one for hc-002 or hc-003, and the final scoreboard caught the cost: on Cobalt 100
the base champion ran 25.1k at 1T against 41.0k at the start of the run (−38.9%). ISPC's NEON
target turns the vector dense code into per-lane scalar loads. hc-020 restores the scalar
routine on NEON only; the x86 assembly is unchanged. From now on every base or shared-code
change gets a Cobalt 100 run before it merges.
| 021 | 2026-10-09 | both | Merge hc-019 (hc-007 + hc-014) and hc-013, approved by Chris | as measured in 019 and 013 | — | — | merged | `hc/champion` |
| 023 | 2026-10-09 | base | Pointer walk over dense chunks (AArch64 paid a zero extension per word) | Cobalt 100 +3% to +8% 1T; x86 ±1% | Zen 3: 60.1k / 433.9k, −0.1% / +0.1%; davepl at 16T 309.2k (ours +39.9%) | Zen 5: stopped; Cobalt 100: +0.0% / +0.2% | REVERT (flat) | `hc/023-base-dense-ptr` |
| 022 | 2026-10-09 | base | Scoreboard: champion `5170556` (with hc-013) against the start, rivals Rust and davepl C++ (1T) | — | Zen 3 (7763): 60.0k / 430.9k, +24.2% / +24.0%; Rust +5.3% / +3.8%; davepl 1T +51.0% | Zen 5 (noisy node, A/A to −19.5% at 4T): 98.2k / 831.5k, +42.5% / +47.1%; Rust +0.1% at 1T, +17.9% at 16T; davepl 1T +35.3%. Cobalt 100: 41.1k, −0.2%; Rust −4.2%, davepl +27.6% | measurement | `hc/champion` |

**022, davepl at 1T.** Measured in the same rounds, davepl's C++ base (`PrimeCPP/solution_5`)
runs 39.7k at 1T on Zen 3 against our 60.0k, 72.0k on Zen 5 against 98.2k, and 32.2k on Cobalt
100 against 41.1k. If it tops the official base table, that must be on multi-thread; later
base runs time it at all threads too.
| r01 | 2026-10-09 | rust | mike-barber Rust: allow AVX-512 (`.cargo/config` disabled it for Skylake Xeons) | Zen 5 +2% to +5%; Zen 3 code identical | n/a (identical: no AVX-512) | Zen 5: 129.9k / 921.2k, +2.4% / +4.9%, 5/5, A/A within 0.2% | KEEP (target-specific rule); starts `hc/rust-champion` | `hc/rust-001-avx512` |

**Rust line.** Rust experiments are measured with `hc-pool.sh` kind `rust`: candidate and
champion are `PrimeRust/solution_1` at two refs, ctrl is our ISPC base champion and ctrl2 is
davepl's C++. Accepted Rust changes collect on `hc/rust-champion`, separate from `hc/champion`.
| r02 | 2026-10-09 | rust | mike-barber Rust: Rust 1.88 on bookworm instead of 1.57 on buster | +2% to +5% from newer LLVM | Zen 3 (7763): 51.4k / 408.6k, −2.2% / −0.6%, 0/5 | Zen 5: stopped | REVERT: the newer toolchain is slower | `hc/rust-002-toolchain` |

**023, dense pointer walk.** Flat on Cobalt 100 and Zen 3, though the AArch64 code lost its
per-word extensions. The arm64 gap to Rust (4%) lies elsewhere.

**r02, newer Rust toolchain.** Rust 1.88 builds a slower binary than 1.57 for this code on Zen 3
(−2.2% at 1T, every round). Old LLVM stays.
| r03 | 2026-10-09 | rust | Rust flag words on a 64-byte boundary (Vec<u64> is 8-byte aligned) | Zen 5 16T +3% to +10%; 1T flat | n/a | Zen 5: 129.4k / 919.7k, +0.1% / −0.2%, stopped after 3 rounds; davepl 16T 713.5k | REVERT: alignment is not the 16T gap | `hc/rust-003-align64` |
| z01 | 2026-10-09 | zig | First Zig entry (`PrimeZig/solution_4`, base and wheel, Zig 0.13, native CPU) against our ISPC entries and davepl | Zig base near ISPC base; Zig wheel 10% to 20% behind ISPC wheel | Zen 3 (7763): wheel 126.0k / 945.9k, +17.7% / +10.1% over ISPC wheel; base 47.3k / 380.2k, −15.9% / −11.2% vs ISPC base, +27.5% / +23.8% vs davepl | Zen 5: wheel 212.1k / 1.61M, +13.1% / +10.5%; base 113.2k / 791.5k, −9.7% / −20.2% vs ISPC base, +22.8% / +11.6% vs davepl | measurement: the Zig wheel is our fastest wheel | `hc/zig-first-pass` |
| 024 | 2026-10-09 | base | `unmasked` in `clear_factor`: every dense vector load and store was masked (13,924 `vmaskmovpd` on AVX2) | AVX2 Zen +2% to +8%, Zen 5 0% to +2% (research pass 2) | Zen 3 (7763): 56.0k / 428.7k, +0.3% / +0.3%, 3/4 | Zen 5: 127.9k / 1.01M, +1.2% / +1.3%, 5/5; Cobalt 100 +0.2% / +0.0% | RERUN with 10 rounds (0–2% band) | `hc/024-base-unmasked` |
| 025 | 2026-10-09 | base | Vector dense on NEON again, on top of hc-024 (the mask, not NEON, caused hc-020) | Cobalt 100 +8% to +15% (research pass 2) | n/a (x86 identical) | n/a | Cobalt 100: 41.0k / 162.9k, −0.2% / −0.6%, 0/5 at 4T: REVERT; NEON stays scalar | `hc/025-base-neon-vector` |
| r04 | 2026-10-09 | rust | Rust pointer-walk sparse loop (12 to 11 instructions per eight ORs on 1.57) | 0% to +2% | Zen 3 (7763): 52.9k / 411.0k, −0.2% / −0.1% | Zen 5: 129.3k / 923.5k, −0.1% / +0.6% | REVERT (flat under Rust 1.57) | `hc/rust-004-sparse-ptr` |
| r05 | 2026-10-09 | rust | r04 plus Rust 1.88 on bookworm | +1% to +4% (dense halves under new LLVM) | Zen 3 (7763): 56.8k / 416.7k, −0.4% / −0.2%, stopped | Zen 5: 49.2k / 370.1k, −61.7% / −59.9% (with AVX-512 on): stopped | REVERT: Rust 1.88 with AVX-512 collapses on Zen 5 | `hc/rust-005-sparse-ptr-toolchain` |
| 026 | 2026-10-09 | base | The factor-3 pass initialises the sieve (no separate zeroing); measured against hc-024 | +1.5% to +2.5% (research pass 2) | Zen 3 (7763): 56.7k / 431.7k, +1.1% / +0.7%, 3/4 at 1T | Zen 5: 129.5k / 1.01M, +0.7% / +0.2%, 4/4 at 1T | below 2%: held with hc-024 for a combined decision | `hc/026-base-init-with-3` |
| 027 | 2026-10-09 | wheel | Fused group loop: two vectors a trip (Zig streams 32 words and beats the ISPC wheel) | +2% to +8% 1T | Zen 3 (7763): 105.4k / 831.8k, −2.7% / −3.9%, stopped | Zen 5: 179.0k / 1.47M, −6.3% / +0.4%, stopped | REVERT: the Zig gain is not the loop width | `hc/027-wheel-fused-x2` |

**024 and 025, the execution mask.** Removing the masks from the dense code gained only 1.2% to
1.4% on Zen 5 and nothing on Zen 3 or Cobalt 100: masked moves inside long unrolled loops cost
little. With the mask gone, NEON's vector dense code is no faster than the scalar code
(−0.2% to −0.6%); two 64-bit lanes per register don't beat paired scalar loads.

**z01, Zig first pass.** The Zig wheel, a port of the ISPC design, beats the ISPC wheel by 18%
at 1T on Zen 3 and 13% on Zen 5, and by 10% at 16 threads. Two differences stand out: its fused
loop streams 32 words per iteration (ISPC: 16 with `avx2-i32x16`), and `applyGroup` is compiled
per member count, so short groups don't stream empty patterns. hc-027 tests the first in ISPC.
The Zig base trails the ISPC base by 10% to 16% at 1T but beats davepl's C++ by 23% to 28%.
| 028 | 2026-10-09 | base | hc-024 + hc-026 together against the champion (measurement for Chris) | Zen 5 +2% to +3%, Zen 3 +1% | Zen 3 (7763): 56.6k / 431.9k, +1.3% / +1.0%, 4/5 at 1T, 5/5 at 16T | Zen 5: 118.2k / 977.5k, +4.2% / +3.4%, 4/4 (noisier node); Cobalt 100: −0.2% / −0.1% (arm64 gate passes) | Chris to decide: recommend merging `hc/026-base-init-with-3` | `hc/026-base-init-with-3` |
| z04 | 2026-10-09 | zig | Zig base: 64-byte-aligned sieve (the arena header left it at 16 mod 64) and a pointer-bounded sparse loop (16 to 11 instructions per eight ORs, no division) | +5% to +15% 1T, most on Zen 5 | Zen 3 (7763): 57.2k / 421.2k, +15.5% / +10.9%, 3/3; ISPC base −3.2%, davepl +49.6% | Zen 5: 124.1k / 1.01M, +9.1% / +27.5%, 4/4; ISPC base −1.5% / +1.6%; Cobalt 100 +0.7% / +0.8% | KEEP: starts `hc/zig-champion` | `hc/zig-004-align-sparse` |
| 024b | 2026-10-09 | base | hc-024 rerun, ten rounds | as 024 | Zen 3 (7763): 56.1k / 428.8k, −0.0% / +0.2%, 3/8 at 1T | Zen 5: 127.9k / 1.00M, +1.9% / +1.4%, 8/8 at 1T, A/A within 1.3% | not kept: Zen 3 flat; see hc-028 | `hc/024-base-unmasked` |
| z01-arm | 2026-10-09 | zig | Zig first pass on Cobalt 100 | | | Cobalt 100: wheel 105.8k / 421.9k, +12.0% / +11.9% over ISPC wheel; base 38.3k / 152.9k, −6.9% / −6.7% vs ISPC base, +18.8% / +18.9% vs davepl | measurement | `hc/zig-first-pass` |
| 029 | 2026-10-09 | both | Build on Ubuntu 26.04 (ISPC 1.28) instead of 24.04 (ISPC 1.22) | +3% to +10% (24% fewer dense instructions in the base) | Zen 3 (7763): wheel 104.7k, +0.6% / −0.3%; base 59.5k, −0.9% / −0.4% | Zen 5: wheel 190.3k, −0.7% / −1.0%; base 120.6k, +2.4% / −0.3% | REVERT (stopped after 3–4 rounds); ISPC 1.22 stays | `hc/029-ubuntu-2604` |
| r01-zen4 | 2026-10-09 | rust | `hc/rust-champion` (r01, AVX-512) against upstream on Zen 4 with AVX-512 | | | Zen 4 (9V74, AVX-512): 76.3k / 608.5k, −0.5% / −0.1%; our ISPC base +6.5% ahead of it; davepl −26% | r01 stands: within 1% on Zen 4, +2.4% / +4.9% on Zen 5 | `hc/rust-champion` |

**029, ISPC 1.28.** Fewer instructions didn't mean more passes: the wheel lost up to 1% and the
base gained only on Zen 5 at 1T. Ubuntu 24.04 with ISPC 1.22 stays. So the Zig wheel's lead is
not simply a newer LLVM either; per-pass allocation is the remaining suspect.
| 030 | 2026-10-10 | wheel | Size the Group scratch to the dense limit (MAXPAT 1024 → 256; 70KB → 20KB). Both reviews | +3–8% (reviews); +0–3% (mine: only touched lines count) | 107.2k / 861.0k, +0.3% / −0.2% | 189.0k / 1.46M, +1.3% / −0.1% | flat (0–2%; 10-round rerun only if node time is left) | `hc/030-wheel-scratch-256` |

**030, scratch size.** The 70KB was mostly never touched: each row uses only L + 16 words, so
the live footprint was already about 20KB. Cobalt 100 is flat too (±0.1%). The wheel's 35% in
the fused loop is not an L1 capacity problem.
| r06 | 2026-10-10 | rust | Extreme dense resets up to 191 (was 129). Both reviews | +2–5% Zen 5 | 53.4k / 416.2k, +1.8% / +1.1% (6/6 rounds) | 95.4k / 709.6k, −26.1% / −22.7% | rejected | `hc/rust-r06-dense-191` |

**r06, Rust dense to 191.** Zen 3 gained a clean 1.8%, but Zen 5 with AVX-512 lost a quarter of
its speed at every thread count. On AVX-512 LLVM vectorises the macro's word resets for 131–191
very differently from those up to 129. The ISPC base's own dense-to-191 (hc-031) is AVX-512 only
and checked in the assembly, so this result doesn't carry over to it.
| r07 | 2026-10-10 | rust | Raw pointer walk in `ResetterSparseU8` (as hc-003). Both reviews | 0–5% | 53.0k / 410.4k, +0.4% / −0.2% | 127.1k / 924.0k, −0.3% / +0.5% | flat; dropped | `hc/rust-r07-sparse-ptr` |

**r07, Rust pointer walk.** Nothing to take: `chunks_exact_mut` already compiles to a pointer
walk. The ISPC base's 12% from hc-003 came from removing 32-bit index arithmetic that Rust never
had.
| 032 | 2026-10-10 | base | Immediate byte offsets in the sparse loop for each odd factor 129–383 (Grok idea 2) | 0–3% | 60.2k / 432.8k, +0.1% / +0.2% | 126.7k / 988.3k, +0.6% / −0.7% | rejected (under 2%; Zen 5 16T lost every round) | `hc/032-base-sparse-imm` |

**032, sparse immediates.** Register offsets were never the cost: the loop is store-bound.
Cobalt 100 +0.4%. Grok's idea 5 (a counted sparse loop) was dropped from the assembly alone
(hc-034, not run): the champion's loop is already an eliminated move, an add and a fused
compare-and-branch, and the counted form compiled to five instructions.
| 031 | 2026-10-10 | base | Dense resets up to 191 on AVX-512, where the vector form still folds (both reviews, idea 1) | +2–5% Zen 5 (mine); +5–13% (Grok) | n/a (byte-identical) | 115.5k / 965.9k, −7.2% / −3.2% (0/6 rounds) | rejected | `hc/031-base-dense-192` |

**031, dense to 191.** The masks fold (no compares or blends in the AVX-512 assembly) and it
still loses 7%: for factors over 128 one vector sweep of the whole sieve costs more than the
sparse loop's 2,600 byte ORs. Rust's r06 lost the same way. AVX2 and SSE4 don't fold past 119
(16,000 blends), which is why `VEC_LIMIT` is 119. Next: hc-036 tests the other direction (96).
| 033 | 2026-10-10 | wheel | Two gangs (32 words) per step in `apply_group`, as the Zig wheel does | +3–8% | 100.0k / 861.2k, +0.6% / +1.2% | 183.2k / 1.50M, −4.0% / +2.0% | rejected (Zen 5 −4%, Cobalt 100 −3%) | `hc/033-wheel-two-gangs` |

**033, two gangs per step.** Not the Zig wheel's secret. The unrolled loop needs 16 live
phase and pointer values on x86 and spilled more (23 reloads and 9 spills per step). The
assembly shows the real difference: Zig addresses each pattern at a fixed offset from the
group (`g + j*8704 + 8*r[j]`), so a member costs one register. hc-035 copies that.
| 036 | 2026-10-10 | base | Dense limit 96 on x86 (NEON stays 128, byte-identical) | 0–3% Zen 5 | 54.1k / 415.3k, −2.5% / −3.1% (0/6) | 125.5k / 988.9k, −0.1% / −0.5% | rejected | `hc/036-base-dense-96` |

**036, dense to 96.** Zen 3 loses 2.5% and Zen 5 is flat, so with hc-031 the cutover is
bracketed: 128 is right for the vector dense code on both machines. The base's dense and
sparse limits are done; the reviews' largest predicted gain (+5–13% from 192–256) was the
wrong direction.
| 037 | 2026-10-10 | wheel | G = 8 on AVX-512 on top of hc-035 (probe; measured against hc-035) | 0–4% | n/a (code identical) | 183.6k / 1.48M, −4.8% / −2.0% (0/6) | rejected | `hc/037-wheel-g8-avx512` |

**037, G = 8 on AVX-512.** Fewer live registers didn't make the bigger group pay. hc-011's
reason may be the extra pattern streams rather than spills: eight 64-byte loads a step
compete with the sieve's own load and store. G = 6 stays.
| 038 | 2026-10-10 | wheel | Wheel dense limit 192 (was 256) | within 2% | 97.2k / 825.7k, −1.7% / −3.1% (0/6) | 188.4k / 1.48M, −0.9% / +1.1% | rejected | `hc/038-wheel-dense-192` |
| 039 | 2026-10-10 | wheel | Wheel dense limit 320 (was 256) | within 2% | 93.4k / 798.4k, −6.9% / −6.6% (0/6) | see note | rejected | `hc/039-wheel-dense-320` |

**038 and 039, wheel dense limit.** 256 is still the optimum with the x16 gangs: 192 loses up
to 3% on Zen 3 and 320 loses 7%. (039's Zen 5 run finished after Zen 3 had already decided it.)
| 035 | 2026-10-10 | wheel | Fused loop reads each pattern from its fixed row of `g->buf` instead of through eight pointers; 64-bit phases (the Zig wheel's addressing) | +3–8% x86 | 10 rounds: 108.0k / 888.8k, +1.6% / +3.4% (16T 10/10) | 9 rounds: 192.3k / 1.50M, +0.5% / +2.0% (16T 9/9) | **kept**, merged into `hc/champion` (`dc5fa37`) | `hc/035-wheel-direct-buf`, `hc/035-tidy` |

**035, fixed-row patterns.** On `avx2-i32x16` the fused loop fell from 139 to 115 instructions
a step, stack reloads from 23 to 12 and sign extensions from nine to none. All threads gained
on every x86 machine: Zen 3 +3.4% (10 rounds, all won), Zen 4 with AVX-512 +3.2% (6/6), Zen 5
+2.0% (9 rounds, all won; Spot preempted both nodes in round 10). One thread gained 0.5% to
1.6%. Cobalt 100 −0.3% (inside the 1% limit) and SSE4 level on the sandbox. The gain is
largest with SMT siblings sharing a core, which fits fewer load-port slots spent on reloads.
It closes only a sliver of the Zig wheel's 12–18% lead; the rest is still unexplained (the
group loop, the sparse loop and allocation now look alike in both).
| diag | 2026-10-10 | wheel | Phase profiles, ISPC wheel against the Zig wheel (TSC timers, diagnostic branches) | n/a | ISPC 124.9k against Zig 106.1k cycles a pass (different nodes) | 82.6k against 61.3k | measurement | `hc/diag-wheel-phases`, `hc/diag-zig-wheel-phases` |
| 041 | 2026-10-10 | wheel | Probe: single-target AVX2 build tuned with `--cpu=znver3` against untuned | n/a | 104.4k / 848.8k, +3.7% / −3.1% | n/a | probe only (multi-target builds can't take `--cpu`) | `hc/041b-probe-avx2-znver3` |
| 042 | 2026-10-10 | wheel | Two gangs per step on top of hc-035 (hc-033 again, now without the spills) | +3–6% Zen 3, 0–3% Zen 5 | 100.4k / 880.3k, +0.2% / −0.4% | 192.0k / 1.51M, −0.4% / +1.0% (8T −1.1%) | rejected (Cobalt 100 +0.6%) | `hc/042-wheel-two-gangs-fixed-rows` |

**diag, phase profiles.** Both wheels spend about half a pass in the fused groups and two
fifths in sparse marking, on Zen 3, Zen 5 and Cobalt 100 alike. The Zig wheel's same-node lead
is 15–19% on Zen 3, 10–13% on Zen 5 and 10–12% on Cobalt 100, and the cross-node profiles put
it in both big phases. A same-node profile is running to confirm. Allocation is ruled out
(persistent buffers changed nothing on the sandbox), and so is vectorising pattern building.

**042, two gangs again.** With fixed-row patterns the loop is 155 instructions per 32 words
(Zig: 142) and still gains nothing. Instruction count in the fused loop is not the limit.

**danielspaangberg, first measurements.** His `5760of30030` wheel, the faithful wheel category's
leader on the leaderboard, runs at 38.0k (Zen 3), 70.2k (Zen 5) and 42.6k (Cobalt 100) passes
at 1T. Ours is 2.6, 2.7 and 2.2 times faster there, and 2.8 to 3.0 times at all threads on Zen.
| 028-confirm | 2026-10-10 | base | hc-028 (merged on Chris's decision) against the champion before it | n/a | 56.0k / 430.6k, +0.7% / +0.9% (6/6) | 116.3k / 950.1k, +2.8% / +1.2% (6/6) | confirmed (Cobalt 100 flat) | `hc/champion` `4c7dc69` |

**028, confirmed.** Against mike-barber's Rust in the same rounds the base now leads at 1T on
Zen 3 (+6.5%) and Zen 5 (+2.8%), and by 15.7% at all threads on Zen 5. It trails by 4% on
Cobalt 100. The partial-group idea for the wheel's dense phase died on arithmetic: the 48
primes from 17 to 251 fill groups of eight (AVX2) and six (AVX-512) exactly.
| 043 | 2026-10-10 | wheel | Sparse loop in the Zig port's form: counted, `#pragma unroll 4`, unsigned 64-bit indices | +3–8% Zen 5, +2–5% Zen 3 | 96.5k / 831.1k, −3.1% / −6.2% (0/6) | 180.0k / 1.22M, −4.2% / −18.9% | rejected (Cobalt 100 −4.0%) | `hc/043-wheel-sparse-zig-form` |

**043, Zig's sparse form.** ISPC's unrolled loop shares one counter across the eight streams and
reloads offsets from the stack (28 stack accesses per 32 marks; Zig's has none), and the counted
loop brings back the extra register that hc-015 removed. The champion's loop stays. The Zig
sparse lead on Zen 5 is real (same-node profile) but not in the loop's shape; what remains is the
per-prime set-up and the tails, which neither profile split out.
| z05 | 2026-10-10 | zig | Zig base: the factor-3 pass initialises the sieve (ISPC hc-026) | +1–4% | 10 rounds: 58.7k / 425.0k, +1.1% / +0.9% (8/10) | 10 rounds: 125.2k / 1.02M, +0.6% / +0.6% (10/10) | rejected under the small-gain rule (Zen 5 under 1%); Cobalt 100 +0.9% | `hc/zig-z05-init-with-3` |

**z05.** Consistent but small: it wins nearly every round everywhere, and only Zen 3 clears 1%.
The six-round run read +2.3% on Zen 5; ten rounds put it at +0.6%. A note for the rule: six
rounds overstate small gains, so the ten-round rerun is doing its job.
| 044 | 2026-10-10 | wheel | Branch-free single tail mark per plane in `sparse_prime` (at most one multiple is left per plane) | +2–6% | 98.0k / 836.2k, −1.9% / −5.2% (0/6) | 189.1k / 1.47M, −1.2% / −1.1% (0/6) | rejected | `hc/044-wheel-sparse-branchless-tail` |

**044, branch-free tails.** The tail branches were predicted well enough; the conditional form
only added work. Harness note from the same hour: `tools/prun.sh` copied `hc-pool.sh` to one
shared file per launch, and the copy truncated it under a running task (the first Zen 3 base
scoreboard task died silently). Each launch now gets its own copy.
| 045 | 2026-10-10 | wheel | Unsigned arithmetic in `start_bit`, as in the Zig port (signed division and remainder by 30 need sign fix-ups; about 1,300 calls a pass) | 0–2% | 110.2k / 937.3k, **+10.3% / +5.9%** (6/6) | 208.9k / 1.57M, **+9.0% / +5.2%** (6/6) | **kept**, merged into `hc/champion` (`059b8f3`); Cobalt 100 +4.5% / +4.4% (6/6) | `hc/045-wheel-unsigned-start-bit` |

**045, unsigned start bits.** One of the largest single gains of the hill climb, from four lines; I predicted
0–2%. It accounts for most of the Zig wheel's sparse lead on Zen 5 (24.0k against 29.9k cycles
a pass): `start_bit` runs eight times per prime, for 162 primes a pass, and each signed `% 30`
and `/ 30` costs a sign correction on top of the multiply. The profiles pointed at the phase;
reading the Zig source line by line found the cause. Lesson for the harness: when a port is
faster, diff the ports' arithmetic types before their loop shapes.
| final4 | 2026-10-10 | both | Final scoreboard: `hc/champion` against the start (`ispc-dev` code), wheel at `059b8f3`, base at `4c7dc69` (final3) | n/a | wheel 110.1k / 938.9k, +35.7% / +33.8%; base 56.0k / 431.8k, +25.3% / +26.0% | wheel 207.6k / 1.57M, +38.0% / +26.6%; base 128.1k / 1.02M, +48.0% / +47.7% | measurement; Zen 4: wheel +21.5%, base +30.0%; Cobalt 100: wheel +55.6%, base +0.2% | `results/hc/final4-wheel`, `final3-base` |
| zig-vs | 2026-10-10 | wheel | The Zig wheel against the new champion (`059b8f3`), same node, 4 rounds | n/a | Zig 119.0k against 110.6k (+7.6%) | Zig 218.7k against 209.0k (+4.6%) | measurement: the gap halved (was 15–19% and 10–13%) | `results/hc/zig-vs-champion-059b8f3` |
| 046 | 2026-10-10 | wheel | Unsigned division in `apply_group`'s phase, the sparse round count and `is_composite` (after hc-045) | 0–2% | 111.5k / 930.5k, +1.5% / −1.0% | 210.7k / 1.58M, +0.5% / +0.0% | rejected (Zen 5 under the small-gain rule's 1%; Cobalt 100 flat) | `hc/046-wheel-unsigned-rest` |
| board | 2026-10-10 | both | Leaderboard check: top 10 faithful 1-bit base entries at 1T, default commands, our nodes against runners 73 and 74 | n/a | same ten, Swift 3rd → 6th; EPYC VM ~17% faster than our Zen 3 | same ten, Swift 1st → 5th; Rust and Nim within 2% of the Threadripper | measurement: `results/leaderboard-check-2026-10-10.md` | `results/hc/board-2026-10-10` |
| f1-alternate | 2026-10-11 | base (grey) | F1: alternate sweep direction per factor | sparse −10% at 1T on Zen 5 | 61.6k / 455.4k, +10.2% / +5.3% | 146.1k / 2.28M (32T), +12.7% / +12.6% | KEEP on `hc/champion-grey` (Zen 4 +9.3%, arm −0.4%; 96T +17.1%) | `hc/f1-alternate` 206ef99 |
| f2-block-16 | 2026-10-11 | base (grey) | F2: blocked sparse phase, 16 KB | +30% at 1T on Zen 5 | 61.2k / 508.5k, +9.4% / +17.8% | 134.4k / 1.19M (D16as_v7), +9.2% / +21.5% | not merged: arm −2.1%; x86-only form does not stack on F1 | `hc/f2-block-16` 23487a8 |
| f2-x86 | 2026-10-11 | base (grey) | F2 on F1, x86 only (NEON identical) | stacks | 62.4k / 513.2k, +1.2% / +12.7% | 141.2k / 1.24M (D16as_v7), −2.9% / +10.1% | REVERT (−3% at 1-8T on Zen 5) | `hc/f2-x86` 20998bc |
| f1-on-f2 | 2026-10-11 | base (grey) | F1 alternation inside F2's blocks too | little | | −1.3% 1T, −2.0% 16T vs F2 | REVERT | `hc/f1-on-f2` 3731ced |
| wheel-f1 | 2026-10-11 | wheel | F1 for the wheel's group and sparse passes | ~0 1T, +3-6% all threads | | −7.0% / −7.5% (32T) | REVERT | `hc/wheel-f1` f3d0e2d |
| wheel-f1-dense | 2026-10-11 | wheel | wheel F1, sparse always ascending | small | | −0.7% / −0.4% (32T) | REVERT | `hc/wheel-f1-dense` |
| f5-fold | 2026-10-11 | base | avx512 x16 per-lane fold | gain | | +8.6% 1T, −5.2% 32T | REVERT | `hc/f5-fold` 9e3a4e2 |
| f5-addr64 | 2026-10-11 | base | `--addressing=64` on the dense loop | small | | +0.2% 1T, +0.9% 32T | no keep (under 1%) | `hc/f5-addr64` 9a976cf |
| idea12-v2 | 2026-10-11 | wheel | IDEAS 12 on the new champion | +1-3% | 112.4k / 947.7k, +0.9% / +1.7% | 222.0k / 3.26M (32T), +1.6% / +1.2% | KEEP (clean, both lineages) | `hc/champion` 1551635 |
| zig-f2 | 2026-10-11 | Zig base (grey) | port F2 | as ISPC | 42.3k / 373.0k, −23.3% / −11.7% | 129.0k / 1.01M, +3.2% / −0.6% | REVERT | `hc/zig-f2-block` 937da9e |
| zig-idea12 | 2026-10-11 | Zig wheel | port IDEAS 12 | +1-3% | +1.8% / +1.1% (14 rounds) | +1.6% / +1.0% (32T) | not kept (Zen 3 straddles) | `hc/zig-idea12` e1a55bb |
| zig-f1 | 2026-10-11 | Zig base (grey) | port F1 | as ISPC | 59.9k / 439.4k, +8.7% / +4.3% | 132.9k / 1.08M, +11.7% / +9.2% | KEEP on `hc/zig-champion-grey` | `hc/zig-f1` 72e5b42 |
| f6-no512 | 2026-10-11 | both | AVX-512 off at 96T | −2% to +4% | | | cancelled (quota wait) | `hc/f6-no512` d6feacb |
| f4-384 | 2026-10-11 | wheel | F4: PRIMES_DENSE_MAX 384 (tuning, extra-faithful) | flat to +2% 1T | Zen 3 (7763): 102.6k / 872.5k, −8.6% ± 1.3 / −8.1% ± 0.3, 0/6 | Zen 5: 207.4k / 1.52M, −6.7% ± 0.9 / −6.9% ± 0.1, 0/6 | REVERT | `hc/f4-dense-384` |
| f4-512 | 2026-10-11 | wheel | F4: PRIMES_DENSE_MAX 512 | flat to +2% 1T | Zen 3: 91.2k / 764.9k, −19.7% ± 1.2 / −19.3% ± 0.4, 0/6 | Zen 5: 167.5k / 1.33M, −17.9% ± 1.6 / −14.1% ± 2.1, 0/6 | REVERT | `hc/f4-dense-512` |
| f4-640 | 2026-10-11 | wheel | F4: PRIMES_DENSE_MAX 640 | flat to +2% 1T | Zen 3: 81.3k / 710.8k, −27.5% ± 0.6 / −24.8% ± 0.3, 0/6 | Zen 5: 174.3k / 1.27M, −21.7% ± 0.7 / −21.9% ± 0.1, 0/6 | REVERT | `hc/f4-dense-640` |

**F4, dense limit 384 to 640 (run ap-20261011T0100Z).** Every step above 256 loses more, on
both machines, every round. The prediction (flat to +2%) was wrong in sign and size: after
hc-035 and hc-045 the grouped dense pass costs far more per extra prime than the sparse pass it
replaces. 192 and 128 queued to find the optimum's other side.
| p-cpp-wheel-idea12 | 2026-10-11 | cpp-wheel | IDEAS 12 ported to the C++ wheel (borrowed from our ISPC wheel) | +2% to +6% 1T | Zen 3: 105.2k / 885.3k, +0.4% ± 1.2 / +1.4% ± 1.0 | Zen 5: 181.5k / 1.36M, +6.2% ± 0.5 / −0.3% ± 0.2 | MORE ROUNDS (Zen 3) | `hc/port-cpp-wheel-idea12` |
| p-rust-wheel-idea12 | 2026-10-11 | rust-wheel | IDEAS 12 ported to the Rust wheel | 0 to +3% 1T | Zen 3: 96.2k / 803.2k, −0.2% ± 2.1 / +0.7% ± 0.6 (8T −1.6%) | Zen 5: 178.3k / 1.30M, −0.5% ± 0.7 / −0.9% ± 0.7 | REVERT | `hc/port-rust-wheel-idea12` |
| s3-crishoj | 2026-10-11 | rival | crishoj 210-wheel (PR 1094) beside our wheels | within 10% of ours | Zen 3: crishoj 87.8k / 645.7k; ISPC wheel 111.7k / 947.7k; Zig wheel 119.2k / 925.7k | Zen 5: crishoj 191.7k / 1.45M; ISPC 222.2k / 1.63M; Zig 217.2k / 1.61M | measurement | `upstream pull/1094` |
| s5-profile | 2026-10-11 | wheel | TSC phase split, Zen 5 | start + pattern 5-15% | | 68k cycles/pass: start offsets 15.3%, pattern 8.2%, group 33.1%, tile 3.2%, sparse 35.0%, scan 5.2% | measurement | `hc/diag-wheel-phases-2` |
| p-cpp-base-f1 | 2026-10-11 | cpp-base | F1 in the C++ base port (grey, borrowed from our ISPC F1) | +8% to +15% 1T | Zen 3: 56.2k / 439.0k, +8.7% ± 0.6 / +9.9% ± 0.1, 6/6 | Zen 5: 153.1k / 1.03M, +16.4% ± 0.2 / +11.0% ± 0.1, 6/6 | KEEP (grey lineage only) | `hc/port-cpp-base-grey` |
| p-rust-base-f1 | 2026-10-11 | rust-base | F1 in the Rust base port (grey) | +8% to +15% 1T | Zen 3: 52.3k / 417.9k, +8.0% ± 0.6 / +6.4% ± 0.3, 6/6 | Zen 5: 137.3k / 890.2k, +22.0% ± 0.7 / +10.6% ± 0.6, 6/6 | KEEP (grey), >20% recheck queued | `hc/port-rust-base-grey` |
| p-cpp-wheel-group32 | 2026-10-11 | cpp-wheel | wheel-group32 loop shape in the C++ wheel (AVX-512 only) | −1% to +3% | Zen 3 (code unchanged): −0.7% ± 0.5 / −0.4% ± 0.7 | Zen 5: +1.2% ± 4.8 / +6.3% ± 1.1, A/A to +6.9% | INCONCLUSIVE (noisy node) | `hc/port-cpp-wheel-group32` |

**F1 on the base ports.** Both keep on their grey branches. With F1 the Rust base port goes from
−14% to +9% against mike-barber's entry at 1T on Zen 5 and to −0.6% on Zen 3; the C++ base port
beats davepl's by 67% on Zen 5. Local runs overstated the C++ gain (+32% local, +16% Zen 5) and
understated the Rust one (+10-15% local, +22% Zen 5).
| p-cpp-wheel-ub | 2026-10-11 | cpp-wheel | Alignment fix: memcpy vector loads/stores (clang ignored aligned(8) on a using alias and faulted) | 0 to +2% | Zen 3: +0.0% ± 0.6 / +1.0% ± 0.6 | Zen 5: +1.1% ± 0.5 / +0.5% ± 0.2 | KEEP (correctness fix, no regression) | `hc/port-cpp-wheel-ub` |
| p-cpp-wheel-clang | 2026-10-11 | cpp-wheel | Build the C++ wheel with clang++ (as the existing C++ entries do), on the fix | +5% to +18% | Zen 3: 122.3k / 989.5k, +20.5% ± 1.1 / +12.9% ± 0.6, 6/6 | Zen 5: 186.3k / 1.57M, +16.2% ± 3.0 / +19.5% ± 0.9, 6/6 | KEEP (Zen 3 >20% recheck queued) | `hc/port-cpp-wheel-champion` |
| p-rust-base-noavx512 | 2026-10-11 | rust-base | Build with -C target-feature=-avx512f, as mike-barber does (target-specific) | +1% to +5% Zen 5 | Zen 3: code unchanged | Zen 5: 123.6k / 959.0k, +10.0% ± 0.4 / +18.5% ± 0.5, 6/6 | KEEP | `hc/port-rust-base-champion` |
| s6-wheel-210 | 2026-10-11 | wheel | mod-210 wheel, 48 planes, run-time starts | Zen 5 1T −5% to +3% | | Zen 5 screen: −39.5% / −35.1% (3 rounds) | REVERT | `hc/wheel-210` |
| p-cpp-base-clang | 2026-10-11 | cpp-base | Build the C++ base with clang++ | −3% to +5% | | Zen 5 screen: −62.6% / −60.3% | REVERT | `hc/port-cpp-base-clang` |
| p-rust-base-mb | 2026-10-11 | rust-base | Per-period dense resetter, masks in registers (mike-barber's extreme_reset) | a few % | | Zen 5 screen: −42.3% / −37.0% | REVERT | `hc/port-rust-base-mb` |
| b1-cobalt-profile | 2026-10-11 | base | ISPC base vs mike-barber phase split on Cobalt 100 | gap in sparse | Cobalt (ns/pass): ours dense 34.7k, sparse 89.2k, scan 5.3k; Rust 33.4k, 90.1k, 6.7k | | measurement: gap in dense (~1% of a pass) + sparse loop test | `hc/diag-base-phases-arm`, `hc/b1-arm-asm` |

**Screens per Chris's rule.** All three local losers lost more on Zen 5 than locally (wheel-210
−30% → −40%, C++ base clang −15% → −63%, Rust resetter −16% → −42%). The rule cost about 45
node-minutes and confirmed each drop. The two keeps of the hour are both compiler or flag
changes copied from the existing entries in each language (clang for C++, AVX-512 off for Rust).
| s5-starts-ef | 2026-10-11 | wheel | Start offsets: p² once, 8 independent products / 30 (extra-faithful, novel) | +3% to +6% 1T | Zen 3: 114.2k / 962.1k, +1.9% ± 0.6 / +1.7% ± 0.5, 6/6 | Zen 5: 234.8k / 1.72M, +5.5% ± 0.2 / +5.2% ± 0.1, 6/6; Cobalt −1.1% ± 0.1 | passes Zen, fails arm gate: not merged (phase 1 frozen) | `hc/s5-starts-ef` |
| s5-tables | 2026-10-11 | wheel | Build-time tables: start offsets (p < 10,000) and patterns (p < 1,024) (permitted) | +5% to +15% 1T | Zen 3: 134.9k / 1.10M, +19.8% ± 1.4 / +16.6% ± 0.4, 6/6 | Zen 5: 274.4k / 1.90M, +23.4% ± 0.5 / +17.2% ± 0.1, 6/6 | KEEP pending >20% recheck and Cobalt | `hc/s5-tables` |
| b1-sparse-last | 2026-10-11 | base | Sparse loop test against the last chunk start (arm64 29 → 28 instr per 8) | Cobalt +1-2% | Zen 3: −0.1% / +0.2% | Zen 5: −1.9% ± 0.1 / −1.5%; Cobalt −0.2% ± 0.4 | REVERT | `hc/b1-sparse-last` |
| p-cpp-wheel-idea12 (z3b) | 2026-10-11 | cpp-wheel | 12 more Zen 3 rounds | | Zen 3: +1.8% ± 0.8 / +1.4% ± 0.6 (12/12, 11/12) | (Zen 5 +6.2% ± 0.5) | KEEP; re-measured on clang | `hc/port-cpp-wheel-idea12` |
| p-rust-base-2 | 2026-10-11 | rust-base | Dense/sparse cutoff 128 → 160 | 0 to +1% | | Zen 5: +0.5% ± 0.1 / −2.1% ± 0.6 | REVERT | `hc/port-rust-base-2` |
| ha-029 / ha-018 / ha-023 | 2026-10-11 | base | history rechecks (Zen 5 screens) | | | 029: −0.4%; 018: +1.2% ± 0.2 1T (3/3, promoted); 023: noisy | 029 REVERT, 018 full run, 023 inconclusive | |

**Stream 5.** The phase profile put start offsets and pattern building at 23.5% of a Zen 5 wheel
pass. Computing the starts as independent products (extra-faithful) bought +5.5% on Zen 5 and
+1.9% on Zen 3 but cost 1.1% on Cobalt 100; tables built at compile time (permitted) bought
+23% / +20%, nearly the whole 23.5%.
| s5-starts-ef-x86 | 2026-10-11 | wheel | s5-starts-ef with start_bits8 off NEON (neon asm = 1551635; x86 asm = s5-starts-ef) | as measured | Zen 3: +1.9% ± 0.6 / +1.7% ± 0.5 (carried by asm identity) | Zen 5: +5.5% ± 0.2 / +5.2% ± 0.1 (carried); Cobalt: champion code | **KEEP**, `hc/champion` 9f62bd6 | `hc/s5-starts-ef-x86` 75191b0 |

**s5-starts-ef-x86.** Kept at Chris's request after the arm gate failed. Guarding the two call
sites leaves the NEON assembly byte-identical to 1551635 and every x86 target's assembly
byte-identical to the measured s5-starts-ef, so its Zen intervals stand without a new run. SSE4
self-test passes and SSE4 is +6% locally. Zen 3 is +1.9%: it clears the general rule (lower
bound +1.3%) but not the 2% that the target-specific rule asks of machines whose code changes;
flagged for Chris.
| sb-base-z5-20 | 2026-10-11 | base | Scoreboard at hc/ispc-ref 1551635: ours / mike-barber Rust, Zen 5, paired per round | tie ±1% | | 1T +3.08% ± 0.12 (20/20); 4T +3.18% ± 0.05 (20/20); per thread 25,993 vs 25,225 (1T), 24,268 vs 23,523 (4T) | WIN | `hc/scoreboard-base` |
| b2-base-fold-1pc | 2026-10-11 | base | F5 x16 fold for the dense loop only when each thread has a core (n = 1 or 2n ≤ hw threads) | +5% to +8% 1T Zen 5 | code unchanged (AVX2, asm identical) | Zen 5: 139.0k / 1.01M, +7.5% ± 0.1 1T, +7.4% 4T and 8T, −0.3% 16T (6/6) | **KEEP**, `hc/champion` 330b3d4 | `hc/b2-base-fold-1pc` |
| ha-018-full | 2026-10-11 | base | hc-018 (sparse two chunks a trip) on 1551635 | +1% Zen 5 | Zen 3: +0.7% ± 0.2 / +0.3% ± 0.4 | Zen 5: +1.2% ± 0.3 / +1.4% ± 0.3; Cobalt +0.1% / −0.4% | REVERT (Zen 3 under +1%) | `hc/018-base-sparse-x2-on-1551635` |
| b2-prefetchw (sparse, dense) | 2026-10-11 | base | prefetchw in the sparse chunk loop / dense loop (x86 only) | 0 to +3% | sparse −3.0% | sparse −5.2% / −11.3%; dense −2.4% | REVERT | `hc/b2-base-*-prefetchw` |
| s5-tables (verify) | 2026-10-11 | wheel (permitted) | fresh-node recheck and Cobalt | | | Zen 5: +23.6% ± 2.5 / +17.0% ± 1.1; Cobalt +13.7% ± 0.2 | **KEEP**, `hc/champion-tables` 90e81f9 | `hc/s5-tables` |

**Base at one thread on Zen 5.** At hc/ispc-ref the base beat mike-barber's Rust by 3.08% ± 0.12
over 20 paired rounds. The F5 fold, used only when each thread has a core to itself, adds 7.5%
there with no change on any other target, which puts the champion about 10.5% ahead at 1T; a
20-round scoreboard of 330b3d4 is running. hc-018 and both prefetches did not survive Zen 3 or
Zen 5.
| p-cpp-wheel-clang-idea12 | 2026-10-11 | cpp-wheel | IDEAS 12 on the clang champion | +1% to +6% | Zen 3: 123.2k / 1.01M, +1.1% ± 0.8 / +1.9% ± 0.7 (6/6) | Zen 5: 204.7k / 1.66M, +1.3% ± 0.5 / +1.9% ± 0.3 (6/6) | **KEEP**, `hc/port-cpp-wheel-champion` 547221c | `hc/port-cpp-wheel-clang-idea12` |
| sb-base-z5-20-new | 2026-10-11 | base | Scoreboard of hc/champion 330b3d4 against mike-barber's Rust, Zen 5, 20 paired rounds | ≈ +10.5% 1T | | 1T +10.44% ± 0.11 (27,807 vs 25,196 per thread), 4T +10.45% ± 0.04, 8T +10.66%, 16T +15.11%; vs 1551635: +7.14% / +7.20% / +7.15% / −0.46% ± 0.11 (20/20 each) | WIN | `hc/champion` 330b3d4 |
| p-cpp-wheel-clang-idea12-r9 | 2026-10-11 | cpp-wheel | re-decided under the per-thread rule (10 more rounds) | | Zen 3: +1.2% ± 0.5 1T, +0.7% ± 0.5 4T, +1.8% 16T | Zen 5: +1.0% ± 0.2 1T, +1.0% ± 0.2 4T, +2.2% 16T | REVERT (per-thread rule); champion back to 3c98356 code (bf7619a) | `hc/port-cpp-wheel-clang-idea12` |
| p0-fold-avx512 | 2026-10-11 | base | fold-1pc on other AVX-512 chips | | Zen 4 (9V74): −2.7% ± 0.2 1T, −2.7% 4T | Intel Ice Lake (8370C): −7.1% ± 0.1 1T, −7.1% 4T | REPORTED to Chris (not fixed this run) | `hc/champion` |
| r9-rust-wheel-pat | 2026-10-11 | rust-wheel | Pattern build word by word, one extending copy (ISPC's build_pattern) | +5% to +8% 1T | Zen 3: +6.1% ± 0.9 / +7.1% ± 1.1 (4T) | Zen 5: 195.1k, +9.2% ± 1.1 / +9.0% ± 0.7 (4T) | **KEEP**, `hc/port-rust-wheel-champion` df94b47 | `hc/port-rust-wheel-pat` |
| r9-cpp-base | 2026-10-11 | cpp-base | 512-bit dense routines for P 65-127 when a thread has a core; gated on Zen 5 (Chris) | +2% to +5% Zen 5 | code unchanged (AVX2) | Zen 5: 139.4k, +5.9% ± 0.1 1T, +5.6% ± 0.2 4T, −1.3% 16T | **KEEP** (target-specific), `hc/port-cpp-base-champion` 558a949 | `hc/port-cpp-base-wide(-zen5)` |
| r9-zig-wheel-group | 2026-10-11 | zig-wheel | write each plane once as tile OR 13-pattern (no separate 13 pass) | 0 to +4% | Zen 3: +2.6% ± 1.6 / +1.7% ± 2.6 | Zen 5: +1.8% ± 0.3 / +1.7% ± 0.5 | MORE ROUNDS (Zen 3) | `hc/zig-wheel-group` |
| p0-solution3 | 2026-10-11 | wheel-tables | PrimeISPC/solution_3 (tables wheel, own label, README per drafts) vs solution_1 | +15% to +20% | Zen 3: 134.6k, +19.1% ± 1.8 / +16.8% ± 0.5 | Zen 5: 275.0k, +16.8% ± 0.5 / +12.2% ± 0.7 | **KEEP** (permitted), `hc/champion-tables` 4a42d98 | `hc/solution3` |
| s1-base-dense-generic | 2026-10-11 | base | generic dense loop for 65 ≤ p < 128 (hot dense code 96-108 KB → 33-37 KB on x86) | Zen 3 −2% to +3% | | Cobalt: −11.0% ± 0.4 1T, −11.0% 4T | REVERT (Cobalt gate) | `hc/base-dense-generic` |
| size-cliff | 2026-10-11 | both | throughput per number against working set, 16 sizes, Zen 3 / Zen 5 / Cobalt | see README | wheel: no cliff at 1M | base: 0.905 (770k) → 0.705 (1M) | measurement | `hc/diag-size` |
| r9-zig-base | 2026-10-11 | zig-base | clear only word 0; the P=3 pass stores without loading (ISPC INIT) | 0 to +2% | Zen 3: 55.8k, +1.1% ± 0.2 / +1.3% ± 0.3 (6/6) | Zen 5: 126.3k, +1.5% ± 0.4 / +1.3% ± 0.2 (6/6) | **KEEP**, `hc/zig-champion-r9` a90b985 | `hc/zig-base-r9` |
| s1-f1-grey | 2026-10-11 | base (grey) | F1 on 3ad0427, for the upstream issue | +8% to +13% | Zen 3: 61.9k, +10.0% ± 0.6 / +9.8% ± 0.4 | Zen 5: 157.3k, +13.9% ± 0.5 / +13.9% ± 0.3 | measurement (grey, never merged) | `hc/f1-on-330b3d4` |
| fold-zen5 (Zen 4, Intel) | 2026-10-11 | base | fold-1pc gated on Zen 5 (Chris) vs 1551635 | no loss off Zen 5 | Zen 4 9V74: +0.1% / +0.1% | Intel 8370C: −0.0% / +0.0% | no loss (Zen 5 check pending) | `hc/fold-zen5` d882ed5 |
| fold-zen5 | 2026-10-11 | base | 16-lane dense path on Zen 5 only (AMD family 1Ah) plus one thread per core (Chris) | Zen 5 +7.5%, no loss elsewhere | Zen 4 9V74: +0.1% / +0.1%; Intel 8370C: −0.0% / +0.0% | Zen 5: 138.8k, +6.8% ± 0.5 / +6.8% ± 0.1 (6/6) | **KEEP**, `hc/champion` 216629d | `hc/fold-zen5` d882ed5 |
| r9-rust-base-dense | 2026-10-11 | rust-base | factors 17-63 one period at a time, masks in registers | 0 to +3% | (moot) | Zen 5: −0.4% ± 0.3 / −0.3% ± 0.1, −5.5% 16T | REVERT | `hc/port-rust-base-dense` |
| s1-tables-compact | 2026-10-11 | wheel-tables (permitted) | one period stored per pattern, extended per pass in scratch (−19% table bytes read) | 0 to +2% on 32 KB L1 | Zen 3: 133.5k, −0.5% ± 1.4 / −0.6% ± 0.3, −4.7% 16T | Zen 5: 265.6k, −2.4% ± 1.8 / −2.7% ± 2.7 | REVERT | `hc/solution3-compact` b48ee0a |
| r9-cpp-base-zen5 | 2026-10-11 | cpp-base | wide path gated on Zen 5 (CPUID family 1Ah) (Chris) | matches ungated on Zen 5 | (8-lane path by construction) | Zen 5: 139.3k, +6.1% ± 0.5 / +5.6% ± 0.2 (3/3); = ungated +0.4% | gate confirmed, `hc/port-cpp-base-champion` 558a949 | `hc/port-cpp-base-wide-zen5` |
| r9-cpp-wheel | 2026-10-11 | cpp-wheel | group rows through one base pointer, per-member wrap limits (ISPC's shape) | +1% to +4% | Zen 3: 119.3k, −2.2% ± 0.8 / −2.8% ± 0.5 (0/6) | Zen 5: 204.9k, +7.0% ± 1.9 / +7.7% ± 0.5 (6/6) | REVERT (Zen 3 loses) | `hc/port-cpp-wheel-r9` e0ca8df |
| r9-rust-wheel-group | 2026-10-11 | rust-wheel | group loop: asserts before, raw pointers inside (170 → 93 instr / 32 words) | +5% to +10% | Zen 3: 102.4k, +6.1% ± 3.2 / +3.2% ± 2.5 (6/6) | Zen 5: 201.1k, +13.1% ± 1.4 / +16.9% ± 1.4 (6/6) | **KEEP**; combined with df94b47 as a8d9f07 (measuring) | `hc/port-rust-wheel-group` 47d9afd |
| r9-zig-wheel-group | 2026-10-11 | zig-wheel | write 13 with the 7×11 tile in one pass per plane | +2% to +5% | Zen 3: 122.0k, +2.4% ± 1.8 / +2.7% ± 1.6 (8 rounds) | Zen 5: 221.7k, +1.8% ± 0.3 / +1.7% ± 0.5 (6/6) | **KEEP**, `hc/zig-champion-r9` 8ba3386 | `hc/zig-wheel-group` 022e479 |
| r9-zig-tables | 2026-10-11 | zig-wheel (permitted) | wheel start offsets and patterns from comptime tables | +10% | Zen 3: 138.3k, +16.8% ± 4.4 / +14.1% ± 1.4 (6/6) | Zen 5: 250.0k, +15.9% ± 2.4 / +12.3% ± 2.8 (6/6) | **KEEP** (permitted), `hc/zig-champion-tables` 0886ddf | `hc/zig-wheel-tables` |
| r9-rust-wheel-combo | 2026-10-11 | rust-wheel | group-loop bounds hoist + pattern fix together, vs pattern fix alone | +10% to +17% Zen 5 | Zen 3: 114.6k, +10.1% ± 6.7 / +7.6% ± 2.2 (6/6) | Zen 5: 221.3k, +13.2% ± 2.0 / +13.9% ± 0.8 (6/6) | **KEEP**, `hc/port-rust-wheel-champion` a8d9f07 | `hc/port-rust-wheel-combo` |
| r9-zig-base-wide | 2026-10-11 | zig-base | dense step twice as wide on Zen 5 (fold-1pc gate) | +2% to +6% Zen 5 | Zen 3: 54.7k, −2.0% ± 0.4 / −2.1% ± 0.1 (0/6) | Zen 5: 113.9k, −8.9% ± 0.7 / −8.7% ± 1.0 (0/6) | REVERT (no 512-bit ops from Zig 0.13 on Zen 5) | `hc/zig-base-wide` 13edc68 |
| r9-zig-tables-group | 2026-10-11 | zig-wheel (permitted) | tables line + one-pass tile\|13 write (13 from the comptime table) | +1% to +3% | Zen 3: 142.1k, +2.1% ± 2.7 / +5.1% ± 1.2 (6/6) | Zen 5: 253.9k, +1.5% ± 0.4 / +1.6% ± 0.4 (6/6) | **KEEP** (permitted), `hc/zig-champion-tables` 138e074 | `hc/zig-tables-group` |
| r9-zig-evex512 | 2026-10-11 | zig (both) | build with `native+evex512` on Zen 5 (build.sh gate) | base +3% to +8% | (byte-identical off Zen 5) | Zen 5 base: +0.0% ± 0.2 / −0.2% ± 0.3; wheel: +0.0% ± 0.1 / −0.1% ± 0.3 | REVERT (gate firing in the image build not verified) | `hc/zig-zen5-evex512` 66c0cce |
| r10-ox-000 | 2026-10-12 | oxcaml | Build the 5.2.0+ox toolchain once per architecture and cache it | amd64 30-60 min, arm64 60-120 min | - | Zen 5: switch 347 s, image 561 s; Cobalt: switch 604 s, image 775 s; 1.2 GB zstd each | measurement | `ispc-dev/ocaml/oxcaml.Dockerfile` |
| r10-ox-001 | 2026-10-12 | oxcaml | Probe SIMD widths, unboxed types, locals, domains | - | - | local: 128/256-bit SIMD work, AVX-512 crashes the emitter; flambda2 already unboxes Int64 in loops; AVX2 on by default from the build CPU | measurement | `hc/ocaml-ox-probe` c144bad |
| r10-ocaml-001 | 2026-10-12 | ocaml-plain | Plain OCaml 5.2 flambda port of our ISPC base design | 2-4x gkpotter faithful | Zen 3: 16.4k at 1T, 62.1k at 4T | Zen 5: 31.6k at 1T, 116.4k at 4T (ISPC base 130k, Rust 119k, gkpotter 1.6k) | control line | `hc/ocaml-plain-base` 0b8d98c |
| r10-ocaml-002 | 2026-10-12 | ocaml-plain | GC space_overhead 1000 from program start | 1T -5% to -10%, 4T +10% to +40% (1T/4T columns) | Zen 3: -0.1% ± 1.5 / -0.5% ± 0.6 (16T +7.0%) | Zen 5: -3.0% ± 3.9 / -0.8% ± 2.0 (16T +16.0%) | REVERT (1T/4T rule); all-threads gain recorded | `hc/ocaml-002-gc-start` 662c2d4 |
| r10-ocaml-003 | 2026-10-12 | ocaml-plain | Profile phases and hot loops | sparse and tag shifts dominate | - | local Xeon: dense OR 54%, sparse 36%; 11 instr/dense word, 10.6/sparse mark | measurement | `results/hc/ocaml-003-profile/` |

**Run 10 notes.** Ledger columns for run 10 read 1T/4T, the deciding thread counts. ocaml-002: the
all-threads gain (+16% Zen 5, +7% Zen 3 at 16T) is real but the rule decides at 1T and 4T, where
it loses on Zen 5. 4T already scales to 92% per thread with the default GC on Zen 5, so the GC
stall the agent saw on the shared container doesn't show on Zen.
| r10-ox-002 | 2026-10-12 | oxcaml | The plain OCaml source compiled by OxCaml (compiler alone) | within ±10% of plain | Zen 3: 17.1k, +8.4% ± 0.4 / +8.6% ± 0.6 (5/5) | Zen 5: 30.3k, −4.1% ± 0.2 / −2.5% ± 0.8 (0/5); Cobalt: 7.3k, +163% / +157% | measurement (the OxCaml line's start, not a keep decision) | `hc/ox-002-port` fe63db5 |
| r10-ox-003 | 2026-10-12 | oxcaml | 256-bit SIMD copy of the dense pattern (borrowed: ISPC hc-002 vector resets) | +10% to +30% at 1T | Zen 3: 25.1k, +41.4% ± 1.3 / +40.2% ± 2.0 (5/5) | Zen 5: 48.6k, +60.5% ± 0.1 / +56.2% ± 0.4 (5/5); Cobalt +0.1% / +0.3% (scalar path) | **KEEP**, `hc/oxcaml-champion` cbcd24d | `hc/ox-003-ext` cbcd24d |
| r10-ocaml-004 | 2026-10-12 | ocaml-plain | Dense OR over two runs per step: one pattern-word load serves two sieve words | +8% to +13% at 1T | Zen 3: 18.0k, +8.5% ± 4.2 / +7.0% ± 1.2 (5/5) | Zen 5: 32.5k, +7.3% ± 5.3 / +4.7% ± 1.7 (5/5); Cobalt +23.3% / +23.3% | **KEEP**, `hc/ocaml-champion` 0aaa340 | `hc/ocaml-004-dense2` 0aaa340 |
| r10-ocaml-005a | 2026-10-12 | ocaml-plain | Dense limit 64 (on ocaml-004) | 0% to +8% | Zen 3: −3.1% ± 0.4 / −3.3% ± 0.7 (0/5) | Zen 5: +1.1% ± 0.6 / +1.0% ± 0.9 (5/5) | REVERT | `hc/ocaml-005-limit64` da786ff |
| r10-ox-004 | 2026-10-12 | oxcaml | Untagged int64# addressing in dense and sparse loops; sparse as one 64-bit-word OR per composite | +5% to +15% at 1T | Zen 3 (2 rounds so far): +16.0% / +15.1% | Zen 5: 55.6k, +22.1% ± 9.4 / +21.0% ± 10.8 (5/5); **Cobalt −27.9% / −25.2%** | REVERT (Cobalt gate); x86-only form as ox-008 | `hc/ox-004-untagged` a8f8435 |
| r10-ocaml-006 | 2026-10-12 | ocaml-plain | Sieve in a word-indexed Int64 Bigarray (profile change 2) | +5% to +15% at 1T | - | local Xeon only: 1T about −8% (15.4k vs 16.6k mean, 6 rounds); dense 8.5 to 7 instr/word, sparse 10.5 to 11.5 (v2) or 17 (v1) | REJECT at the local gate (slower; fast form needs an Obj.magic byte view) | `hc/ocaml-006-bigarray` 3d1e663 |
| r10-ocaml-005b | 2026-10-12 | ocaml-plain | Dense limit 96 (on ocaml-004) | 0% to +8% | Zen 3: 17.0k, +0.4% ± 1.0 / +0.5% ± 0.6 (4/5) | Zen 5: 33.6k, +1.9% ± 0.6 / +1.6% ± 0.4 (5/5) | REVERT (Zen 3 can't reach +1%) | `hc/ocaml-005-limit96` c620f30 |
| r10-ox-006 | 2026-10-12 | oxcaml | 256-bit OR over two runs per step (borrowed: plain ocaml-004) | +3% to +8% | Zen 3: 25.0k, +3.1% ± 1.0 / +3.3% ± 0.4 (5/5) | Zen 5: 47.0k, +4.6% ± 9.3 / +7.5% ± 3.5 (noisy node) | **KEEP** on cbcd24d; to combine with ox-008 as ox-011 | `hc/ox-006-two-runs` 2ef6a1d |
| r10-ox-007 | 2026-10-12 | oxcaml | Sparse in bit order: constant masks, untagged word ORs (shared code) | x86 +8% to +20% | Zen 3: 30.7k, +27.9% ± 0.1 / +27.1% ± 1.8 (5/5) | Zen 5: 60.8k, +32.8% ± 2.1 / +30.5% ± 2.0 (5/5); **Cobalt −27.6% / −25.1%** | REVERT (Cobalt gate); x86-only form is ox-009 | `hc/ox-007-sparse` 0245d04 |
| r10-ox-008 | 2026-10-12 | oxcaml | ox-004 on x86 only (per-architecture kernels) | Zen 5 +15-25%, Zen 3 +12-18%; Cobalt within 1% | Zen 3: 29.8k, +17.4% / +16.4% (lower bound +12.1%) | Zen 5: 60.5k, +26.6% ± 1.7 / +26.3% ± 1.1; Cobalt +0.0% / +0.2% | **KEEP**, `hc/oxcaml-champion` a4e63af | `hc/ox-008-x86-untagged` a4e63af |
| r10-ox-009 | 2026-10-12 | oxcaml | ox-007's constant-mask sparse form inside the x86-only kernel (on ox-008) | +5% to +10% at 1T | Zen 3: 31.4k, +12.6% ± 0.1 / +11.7% ± 0.6 (5/5) | Zen 5: 64.7k, +5.8% ± 0.2 / +5.3% ± 0.8 (5/5); arm64 byte-identical | **KEEP**, `hc/oxcaml-champion` 4f1ba99 | `hc/ox-009-x86-constmask` 4f1ba99 |
| r10-ox-010 | 2026-10-12 | oxcaml | Arm dense: two runs per step (borrowed: plain ocaml-004), Arm-only | Cobalt +10% to +25% | x86 byte-identical | Cobalt: 7.3k, −0.4% ± 0.0 / −0.6% ± 0.4 (0/5) | REVERT | `hc/ox-010-scalar-two-runs` cf08b1c |
| r10-ox-013 | 2026-10-12 | oxcaml | x86 sparse OR width: 16 or 32 bits instead of unaligned 64 (fewer cache-line crossings) | 0% to +5% | - | local Xeon: 32-bit −5.8%, 16-bit −7.0% at 1T (3 rounds); 6.9 vs 4.9 instr/composite (no int32 constant folding; 16-bit is a tagged int) | REJECT at the local gate | `hc/ox-013-sparse-width` c9c9cf3 |
| r10-ox-011 | 2026-10-12 | oxcaml | Two runs per step in the x86 untagged dense loop (ox-006 on ox-008) | +2% to +5% over a4e63af | Zen 3: 31.4k, +4.8% ± 0.9 / +4.4% ± 2.0 (5/5) | Zen 5: 65.7k, +7.5% ± 1.2 / +7.1% ± 1.2 (5/5); arm64 byte-identical | **KEEP** (vs a4e63af); combined with ox-009 as ox-014 | `hc/ox-011-x86-two-runs` c99a179 |
| r10-ox-015 | 2026-10-12 | oxcaml | x86 sparse: two chunks per loop iteration (halve loop overhead) | +2% to +6% | - | local Xeon: sparse −3% (inside noise), whole pass −1.5% at 1T; 4.9 to 4.6 instr/composite, no faster | REJECT at the local gate | `hc/ox-015-sparse-unroll` 1814c90 |
| r10-ox-014 | 2026-10-12 | oxcaml | Merge of the two kept changes: ox-011 (x86 dense two runs) + ox-009 (x86 constant-mask sparse) | +4% to +8% over 4f1ba99 | Zen 3: 32.4k, +4.2% ± 0.5 / +4.5% ± 1.1 (5/5) | Zen 5: 69.3k, +7.7% ± 1.6 / +7.4% ± 0.7 (5/5); arm64 byte-identical | **KEEP**, `hc/oxcaml-champion` 997f71f | `hc/ox-014-combo` 997f71f |
| r10-ox-017 | 2026-10-12 | oxcaml | x86 pattern build: 256-bit zeroing, untagged single-bit ORs (Arm code moved, unchanged) | +1% to +4% | Zen 3: 37.0k, +7.4% ± 4.1 / +7.1% ± 2.6 (5/5) | Zen 5: 72.4k, +3.3% ± 0.1 / +2.9% ± 0.6 (5/5); Cobalt +0.0% / −0.1% | **KEEP**, `hc/oxcaml-champion` 2d1ae49 | `hc/ox-017-pattern` 2d1ae49 |
| r10-ox-016 | 2026-10-12 | oxcaml | x86 dense: four runs per step (on 997f71f) | +0% to +4% | Zen 3: first 5 rounds +1.0% / +1.2% (4T lower bound +1.0%); 8 more: 32.8k, +1.0% ± 0.2 / +1.3% ± 0.2 (8/8) | Zen 5: 71.3k, +3.1% ± 0.8 / +2.9% ± 1.1 (5/5); arm64 byte-identical | **KEEP**; merged with ox-017 as ox-019 | `hc/ox-016-four-runs` af2adaf |
| r10-ox-018 | 2026-10-12 | oxcaml | Arm diagnosis: allocation and compiled dense loop on Cobalt | boxing | - | Cobalt: 6 minor words per pass (no boxing); each 64-bit store in the dense copy is `ldr; dmb ishld; str` (OCaml 5 memory-model barrier before stores to mutable memory) | measurement | `hc/ox-018-armdiag` 8233d3a |
| r10-ox-020 | 2026-10-12 | oxcaml | Arm: which 64-bit store forms avoid the barrier (micro-benchmark on Cobalt, 62.5 KB copy) | float or 32-bit stores avoid it | - | Cobalt, ns per copy: every 64-bit integer store form 18.8-19.1k (Bytes, int64#, Bigarray, bigstring, int64# array); 32-bit pairs 6.2k; byte stores 24.6k; float array 2.0k; floats into Bytes via Obj.magic 3.7k | measurement | `hc/ox-020-armstore` ad463f1 |
| r10-ocaml-007 | 2026-10-12 | ocaml-plain | 32-bit stores in the dense loop (avoid the Arm store barrier), one source for all targets | Cobalt +60-120%, x86 −5% to +5% | - | local x86: about −38% at 1T (11.3k vs 18.3k, 3 rounds); no Int32 boxing, but twice the memory operations | REJECT at the local gate (over 30% slower); an Arm-only build would need a per-architecture file as OxCaml has | `hc/ocaml-007-set32` e7e8016 |
| r10-ox-019 | 2026-10-12 | oxcaml | Merge ox-016 (four runs per step) with the champion's ox-017 (pattern build) | +1% to +4% over 2d1ae49 | Zen 3: 36.8k, −0.7% ± 0.5 / −1.2% ± 1.8 (0/5) | Zen 5 (3 rounds): 75.1k, +4.2% ± 0.1 / +3.1% ± 1.8 | REVERT (Zen 3 4T −1.2%); four runs per step stays out | `hc/ox-019-combo` 4dc5560 |
| r10-ox-021 | 2026-10-12 | oxcaml | Arm dense copy and pattern build with 32-bit stores (no store barrier); Arm-only | Cobalt +60% to +120% | x86 byte-identical | Cobalt: 11.8k, **+61.4% ± 0.0 / +55.8% ± 1.5** (5/5) | **KEEP** (target-specific: decided on Cobalt), `hc/oxcaml-champion` 37e493e | `hc/ox-021-arm-set32` 37e493e |
| r10-final | 2026-10-12 | both OCaml lines | Final scoreboard, 6 rounds, all controls | - | Zen 3 1T: OxCaml 37.2k, plain 18.2k, ISPC 60.0k, Rust 56.5k, gkpotter 0.8k | Zen 5 1T: OxCaml 72.2k, plain 32.9k, ISPC 138.9k, Rust 126.3k, gkpotter 1.6k; Cobalt 1T: 11.8k, 3.4k, 42.1k, 42.9k, 0.6k | measurement | `results/hc/r10-final/` |
| f2-on-submitted | 2026-10-12 | base (grey, measurement) | F2: sparse factors cleared in 16 KB blocks, on the submitted base build (d2ef0d6), F1 out | - | Zen 3 (7763): 66.2k, +10.6% ± 1.3 / +10.3% ± 2.4 (7/7); all threads +18.5% | Zen 5 (9V45): 154.1k, +10.8% ± 0.2 / +10.6% ± 0.3 (7/7); all threads +21.8% | measurement (grey, never merged) | `hc/f2-on-submitted` 9faa02e |
