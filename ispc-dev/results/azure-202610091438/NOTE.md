Batch Spot smoke test on Standard_D4ps_v6 (Azure Cobalt 100, Neoverse-N2, 4 vCPU), solution_1 at
commit 83c20ec (threshold 256, x8 NEON gang). NOTE: "old" here is BASE=HEAD, which already
contained 83c20ec, so old == new; the run is a valid Cobalt 100 measurement, not an A/B.
Result: ~55.0k passes 1T, ~219k @4, ~109.9k @2.
