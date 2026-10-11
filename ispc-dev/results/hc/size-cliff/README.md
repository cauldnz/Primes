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

## Results

(filled in when the runs land)
