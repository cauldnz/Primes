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
