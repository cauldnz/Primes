# Size cliff: throughput against working set (run ap-20261011T0645Z, stream 1 step 1)

Both ISPC entries at hc/champion 330b3d4, sieve size set by `PRIMES_SIZE` (diagnostic build
`hc/diag-size` db6cf2e), 16 sizes from 250,000 to 2,000,000, 1T and one per core, 3 rounds, on
Zen 3 (32 KB L1D), Zen 5 (48 KB) and Cobalt 100 (64 KB). Throughput per number = passes × n / 5 s,
normalised by n·ln ln n (the sieve's work per number).

Working set: wheel 8 planes of ceil(n/30) bits (32.6 KB at 1M: over 32 KB from 1,000,000, over
48 KB at 1.45M, over 64 KB at 2M); base n/16 bytes (61 KB at 1M: over 32 KB at 600k, over 48 KB at
850k, over 64 KB at 1.05M).

## Predictions (written before the runs, from RUN-PLAN and the profiles)

1. Wheel, Zen 3: a drop of 10% to 20% in normalised throughput between 920k–960k and 1.0M–1.1M
   (crossing 32 KB). The 1M point sits just past the edge.
2. Wheel, Zen 5: no step between 0.9M and 1.1M; a smaller step (5% to 10%) between 1.3M and
   1.45M (crossing 48 KB).
3. Base, Zen 5: a drop of 5% to 15% between 770k and 850k (crossing 48 KB).
4. Base, Zen 3: a step between 500k and 600k (crossing 32 KB), similar size; flat after, since
   1M is already far out.
5. Cobalt (64 KB): wheel flat to 1.6M; base step between 1.0M and 1.05M (crossing 64 KB: the
   official 1M size sits just inside).
6. One per core tracks 1T within 3% everywhere (no sharing).

## Results (3 rounds each; columns are threads: 1, 4, 8 and 16 on the 16-vCPU Zen nodes, 1, 2, 4 on Cobalt)

What it says:

- **The wheel has no cliff at 1M on Zen 3.** Per-thread throughput per number is on one plateau
  (1.27-1.30 relative to 250k) from 700k to 1.05M, so the 33 KB wheel just over Zen 3's 32 KB L1
  costs about nothing; it falls 2% by 1.1M and 8% by 1.3M. Prediction 1 (a 10-20% drop) was wrong.
  RUN-PLAN stream 1 step 2 runs only on a Zen 3 wheel cliff, so the plane-order, plane-halves,
  plane-by-plane sparse and scratch-trim candidates are not built this run.
- **Wheel, Zen 5**: flat to 1.1M, −5% at 1.3M (crossing 48 KB), as predicted (2).
- **The base pays for L1 on Zen 5**: 0.905 at 770k (47 KB) → 0.813 at 850k (−10%) → 0.705 at 1M,
  so fitting in 48 KB is worth about 22-28% at the official size (prediction 3: 5-15% near 770k,
  low). The base rules fix 62.5 KB; only blocking (F2, grey) reaches it. This is the clean number
  for the upstream F1/F2 question.
- **Base, Zen 3**: no single step; the steepest stretch is 500k-700k (crossing 32 KB, −16%).
- **Cobalt (64 KB)**: wheel flat to 1.6M (prediction 5 holds); base −6.6% from 1.0M to 1.1M,
  crossing 64 KB, so the official 1M size sits just inside its L1.
- **One per core tracks 1T** within about 1% everywhere (prediction 6 holds); with SMT (16T on
  Zen) the base loses a further 3-5% across the range.

Calibration: 4 of 6 predictions held (2, 4 partly, 5, 6); 1 wrong, 3 low.

```

### AMD EPYC 7763 64-Core Processor (results/hc/size-cliff/Standard_D16a_v4.txt)

wheel: per-thread throughput per number, relative to 250,000 (1.000)

| n | working set KB | 1T | 4T | 8T | 16T |
|---|---|---|---|---|---|
| 250,000 | 8.1 | 1.000 | 1.000 | 1.000 | 1.000 |
| 400,000 | 13.0 | 1.183 | 1.172 | 1.171 | 1.200 |
| 500,000 | 16.3 | 1.232 | 1.217 | 1.220 | 1.259 |
| 600,000 | 19.5 | 1.273 | 1.252 | 1.256 | 1.311 |
| 700,000 | 22.8 | 1.292 | 1.284 | 1.289 | 1.328 |
| 770,000 | 25.1 | 1.298 | 1.279 | 1.280 | 1.328 |
| 850,000 | 27.7 | 1.302 | 1.285 | 1.291 | 1.313 |
| 920,000 | 29.9 | 1.294 | 1.273 | 1.281 | 1.249 |
| 960,000 | 31.2 | 1.275 | 1.259 | 1.263 | 1.151 |
| 1,000,000 | 32.6 | 1.298 | 1.298 | 1.298 | 1.245 |
| 1,050,000 | 34.2 | 1.288 | 1.270 | 1.277 | 1.253 |
| 1,100,000 | 35.8 | 1.268 | 1.245 | 1.259 | 1.230 |
| 1,300,000 | 42.3 | 1.188 | 1.176 | 1.183 | 1.156 |
| 1,450,000 | 47.2 | 1.145 | 1.131 | 1.134 | 1.099 |
| 1,600,000 | 52.1 | 1.094 | 1.083 | 1.087 | 1.064 |
| 2,000,000 | 65.1 | 1.040 | 1.031 | 1.036 | 1.013 |

base: per-thread throughput per number, relative to 250,000 (1.000)

| n | working set KB | 1T | 4T | 8T | 16T |
|---|---|---|---|---|---|
| 250,000 | 15.3 | 1.000 | 1.000 | 1.000 | 1.000 |
| 400,000 | 24.4 | 0.927 | 0.916 | 0.916 | 0.820 |
| 500,000 | 30.5 | 0.877 | 0.872 | 0.870 | 0.741 |
| 600,000 | 36.6 | 0.807 | 0.802 | 0.801 | 0.694 |
| 700,000 | 42.7 | 0.733 | 0.729 | 0.728 | 0.661 |
| 770,000 | 47.0 | 0.698 | 0.694 | 0.693 | 0.642 |
| 850,000 | 51.9 | 0.667 | 0.663 | 0.662 | 0.624 |
| 920,000 | 56.2 | 0.643 | 0.644 | 0.642 | 0.608 |
| 960,000 | 58.6 | 0.638 | 0.634 | 0.634 | 0.601 |
| 1,000,000 | 61.0 | 0.631 | 0.627 | 0.626 | 0.595 |
| 1,050,000 | 64.1 | 0.619 | 0.617 | 0.616 | 0.587 |
| 1,100,000 | 67.1 | 0.609 | 0.607 | 0.606 | 0.579 |
| 1,300,000 | 79.3 | 0.582 | 0.578 | 0.578 | 0.551 |
| 1,450,000 | 88.5 | 0.564 | 0.561 | 0.560 | 0.536 |
| 1,600,000 | 97.7 | 0.550 | 0.547 | 0.546 | 0.522 |
| 2,000,000 | 122.1 | 0.521 | 0.520 | 0.517 | 0.491 |


### AMD EPYC 9V45 96-Core Processor (results/hc/size-cliff/Standard_D16as_v7.txt)

wheel: per-thread throughput per number, relative to 250,000 (1.000)

| n | working set KB | 1T | 4T | 8T | 16T |
|---|---|---|---|---|---|
| 250,000 | 8.1 | 1.000 | 1.000 | 1.000 | 1.000 |
| 400,000 | 13.0 | 1.195 | 1.175 | 1.192 | 1.134 |
| 500,000 | 16.3 | 1.264 | 1.259 | 1.261 | 1.187 |
| 600,000 | 19.5 | 1.294 | 1.295 | 1.289 | 1.207 |
| 700,000 | 22.8 | 1.314 | 1.318 | 1.310 | 1.219 |
| 770,000 | 25.1 | 1.304 | 1.274 | 1.278 | 1.217 |
| 850,000 | 27.7 | 1.324 | 1.328 | 1.323 | 1.216 |
| 920,000 | 29.9 | 1.334 | 1.321 | 1.327 | 1.217 |
| 960,000 | 31.2 | 1.322 | 1.312 | 1.314 | 1.172 |
| 1,000,000 | 32.6 | 1.331 | 1.315 | 1.318 | 1.174 |
| 1,050,000 | 34.2 | 1.316 | 1.305 | 1.316 | 1.178 |
| 1,100,000 | 35.8 | 1.308 | 1.274 | 1.301 | 1.174 |
| 1,300,000 | 42.3 | 1.259 | 1.209 | 1.262 | 1.104 |
| 1,450,000 | 47.2 | 1.238 | 1.193 | 1.233 | 1.067 |
| 1,600,000 | 52.1 | 1.192 | 1.142 | 1.173 | 1.049 |
| 2,000,000 | 65.1 | 1.079 | 1.026 | 1.050 | 0.978 |

base: per-thread throughput per number, relative to 250,000 (1.000)

| n | working set KB | 1T | 4T | 8T | 16T |
|---|---|---|---|---|---|
| 250,000 | 15.3 | 1.000 | 1.000 | 1.000 | 1.000 |
| 400,000 | 24.4 | 0.997 | 1.002 | 1.000 | 0.910 |
| 500,000 | 30.5 | 0.987 | 0.990 | 0.990 | 0.925 |
| 600,000 | 36.6 | 0.959 | 0.959 | 0.961 | 0.848 |
| 700,000 | 42.7 | 0.934 | 0.933 | 0.934 | 0.785 |
| 770,000 | 47.0 | 0.905 | 0.901 | 0.895 | 0.753 |
| 850,000 | 51.9 | 0.813 | 0.802 | 0.797 | 0.715 |
| 920,000 | 56.2 | 0.757 | 0.750 | 0.742 | 0.689 |
| 960,000 | 58.6 | 0.727 | 0.715 | 0.705 | 0.677 |
| 1,000,000 | 61.0 | 0.705 | 0.695 | 0.686 | 0.668 |
| 1,050,000 | 64.1 | 0.677 | 0.668 | 0.659 | 0.658 |
| 1,100,000 | 67.1 | 0.663 | 0.656 | 0.650 | 0.647 |
| 1,300,000 | 79.3 | 0.624 | 0.616 | 0.608 | 0.601 |
| 1,450,000 | 88.5 | 0.602 | 0.597 | 0.589 | 0.582 |
| 1,600,000 | 97.7 | 0.586 | 0.578 | 0.569 | 0.556 |
| 2,000,000 | 122.1 | 0.545 | 0.538 | 0.530 | 0.512 |


### Neoverse-N2 (results/hc/size-cliff/Standard_D4ps_v6.txt)

wheel: per-thread throughput per number, relative to 250,000 (1.000)

| n | working set KB | 1T | 2T | 4T |
|---|---|---|---|---|
| 250,000 | 8.1 | 1.000 | 1.000 | 1.000 |
| 400,000 | 13.0 | 1.121 | 1.122 | 1.122 |
| 500,000 | 16.3 | 1.151 | 1.151 | 1.152 |
| 600,000 | 19.5 | 1.168 | 1.168 | 1.167 |
| 700,000 | 22.8 | 1.173 | 1.174 | 1.174 |
| 770,000 | 25.1 | 1.174 | 1.171 | 1.171 |
| 850,000 | 27.7 | 1.173 | 1.174 | 1.173 |
| 920,000 | 29.9 | 1.176 | 1.175 | 1.176 |
| 960,000 | 31.2 | 1.172 | 1.171 | 1.170 |
| 1,000,000 | 32.6 | 1.170 | 1.172 | 1.172 |
| 1,050,000 | 34.2 | 1.168 | 1.165 | 1.165 |
| 1,100,000 | 35.8 | 1.162 | 1.164 | 1.164 |
| 1,300,000 | 42.3 | 1.151 | 1.150 | 1.150 |
| 1,450,000 | 47.2 | 1.141 | 1.142 | 1.142 |
| 1,600,000 | 52.1 | 1.130 | 1.131 | 1.130 |
| 2,000,000 | 65.1 | 1.100 | 1.095 | 1.096 |

base: per-thread throughput per number, relative to 250,000 (1.000)

| n | working set KB | 1T | 2T | 4T |
|---|---|---|---|---|
| 250,000 | 15.3 | 1.000 | 1.000 | 1.000 |
| 400,000 | 24.4 | 0.879 | 0.879 | 0.878 |
| 500,000 | 30.5 | 0.827 | 0.828 | 0.827 |
| 600,000 | 36.6 | 0.787 | 0.786 | 0.787 |
| 700,000 | 42.7 | 0.757 | 0.757 | 0.757 |
| 770,000 | 47.0 | 0.739 | 0.739 | 0.739 |
| 850,000 | 51.9 | 0.719 | 0.712 | 0.711 |
| 920,000 | 56.2 | 0.693 | 0.697 | 0.697 |
| 960,000 | 58.6 | 0.694 | 0.691 | 0.690 |
| 1,000,000 | 61.0 | 0.680 | 0.678 | 0.678 |
| 1,050,000 | 64.1 | 0.667 | 0.666 | 0.666 |
| 1,100,000 | 67.1 | 0.635 | 0.634 | 0.634 |
| 1,300,000 | 79.3 | 0.519 | 0.518 | 0.518 |
| 1,450,000 | 88.5 | 0.480 | 0.480 | 0.480 |
| 1,600,000 | 97.7 | 0.459 | 0.459 | 0.459 |
| 2,000,000 | 122.1 | 0.430 | 0.430 | 0.430 |

```
