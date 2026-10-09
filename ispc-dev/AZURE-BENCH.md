# The test bench: Azure Batch

The climber benchmarks every candidate on real AMD and Arm server cores, not on the machine it
runs on. It does that through Azure Batch. This note says why Batch, what to expect when you set
up your own, and how. The script is `tools/azure-setup.sh`.

## Why Batch rather than plain VMs

**Batch can reach machines your subscription can't.** In Batch-service mode, the default, pool
nodes run in subscriptions that Batch itself manages. Your subscription's VM quotas and offer
restrictions don't apply to them; the Batch account's own quotas do. On 9 October every Spot VM
we tried to create directly failed preflight with `SkuNotAvailable` ("Capacity Restrictions") in
every region, because of the subscription's offer. The same VM sizes as Spot nodes in a Batch
pool worked at once. That gave us Zen 3 (`D16a_v4`), Zen 4 (`D16as_v6`), Zen 5 (`D16as_v7`) and
Cobalt 100 (`D4ps_v6`) nodes for a few cents an hour each.

Batch also fits the climber's way of working:
- **Pools clean up after themselves.** Each pool's autoscale formula drops it to zero nodes at a
  deadline, whatever happens to the session that made it.
- **Tasks outlive the session.** A task uploads its output to storage when it ends, so the climber
  can sleep, pause or move machines and collect the result on its next tick.
- **One account, one resource group, one narrow login.** The climber's service principal has
  Contributor on that group and nothing else.

Batch can't make capacity appear. Spot nodes still depend on spare capacity in the region and can
be pre-empted; on 9 October Spot took both Zen 5 nodes mid-run. The protocol's controls in every
round, and the salvage of finished rounds, exist for that.

## Spot quota: expect a support request

A new Batch account usually starts with too few Spot (low-priority) vCPUs for a climb, which
wants about 64: four 16-vCPU nodes. Raising it takes a quota request: in the portal, open the
Batch account, then Quotas, then Request quota increase, and ask for Spot/low-priority vCPUs.
It's free. Ours was approved quickly, for 128 Spot vCPUs. `azure-setup.sh up` checks the quota
and tells you when to ask.

Ask early, before the first run you care about. Without the quota, pools create without error
and then sit at zero nodes.

## Setting it up

You need the Azure CLI, logged in (`az login`) as someone who can create a resource group and an
app registration.

```bash
LOCATION=westus2 bash ispc-dev/tools/azure-setup.sh up    # group, storage, Batch account, principal
bash ispc-dev/tools/azure-setup.sh check                  # the principal reaches Batch and nothing else
bash ispc-dev/tools/azure-setup.sh rotate                 # before each run: a fresh 12-hour secret
bash ispc-dev/tools/azure-setup.sh down                   # delete it all
```

`up` writes an env file (mode 600) with six lines: four `AZURE_*` settings for the login, plus
`BATCH_ACCOUNT` and `BATCH_RG`. Put them in the environment of the session that runs the climber
and allow its network to reach `management.azure.com`, `login.microsoftonline.com`,
`*.batch.azure.com` and `*.blob.core.windows.net` (`CLOUD-RUNBOOK.md` has the details for a
Claude Code cloud environment). Never commit the file.

Pick a region where the sizes you want have Spot capacity. All four sizes above exist in
`westus2`; check `CLOUD-RUNBOOK.md` for which size gave which CPU, and read the `Model name` line
of every log, because a size doesn't always map to the same CPU.
