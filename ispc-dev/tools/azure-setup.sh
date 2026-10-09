#!/bin/bash
# azure-setup.sh: stand up (and tear down) your own Azure Batch test bench for the climber.
#
#   azure-setup.sh up        create the resource group, a storage account, a Batch account linked
#                            to it, and a service principal that can touch only that group;
#                            then issue a short-lived secret and write the env file
#   azure-setup.sh rotate    issue a fresh secret (old ones stop working) and rewrite the env file
#   azure-setup.sh check     log in as the service principal and list pools, as a run would
#   azure-setup.sh down      delete the resource group and the service principal
#
# You run this yourself, logged in to the Azure CLI (`az login`) as someone who can create
# resource groups and app registrations. The climber never runs it.
#
# Settings (environment variables; defaults in brackets):
#   AZURE_SUBSCRIPTION_ID  subscription to use [the CLI's current one]
#   LOCATION               Azure region [westus2]. Pick one where the VM sizes you want to test
#                          have Spot capacity; the Zen 3/4/5 and Cobalt sizes all exist in westus2.
#   BATCH_RG               resource group [rg-hillclimb]
#   PREFIX                 start of the generated account names, lowercase letters [hc]
#   SECRET_HOURS           lifetime of each secret [12]. Keep it to one run; rotate for the next.
#   ENV_FILE               where to write the settings [./hillclimb-azure.env]
#   SPOT_VCPUS             Spot vCPUs you expect to use, for the quota check [64]
#   SP_NAME                service principal display name [BATCH_RG-climber]
#
# What it creates, all inside BATCH_RG:
#   - a general-purpose v2 storage account (task output, staged builds);
#   - a Batch account in Batch-service mode, with that storage as its auto-storage;
#   - a service principal with Contributor on BATCH_RG and nothing else.
# Pools are not created here: the climber creates them per run (hc-pool.sh up) with a deadline,
# and they scale to zero on their own. An idle account costs nothing but a few cents of storage.
#
# The env file holds a live secret. It is written with mode 600. Never commit it, never paste it
# into a chat; put its lines into the environment settings of the session that runs the climber.
set -euo pipefail

CMD=${1:-help}
LOCATION=${LOCATION:-westus2}
BATCH_RG=${BATCH_RG:-rg-hillclimb}
PREFIX=${PREFIX:-hc}
SECRET_HOURS=${SECRET_HOURS:-12}
ENV_FILE=${ENV_FILE:-./hillclimb-azure.env}
SPOT_VCPUS=${SPOT_VCPUS:-64}
SP_NAME=${SP_NAME:-$BATCH_RG-climber}

die() { echo "azure-setup: $*" >&2; exit 1; }
say() { echo "== $*"; }
command -v az >/dev/null || die "the Azure CLI is not installed (https://aka.ms/azcli)"

sub() {
    SUB=${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv 2>/dev/null)} \
        || die "not logged in: run az login first"
    [ -n "$SUB" ] || die "not logged in: run az login first"
    TENANT=$(az account show --subscription "$SUB" --query tenantId -o tsv)
}

# Names that already exist in the group are reused, so `up` is safe to run twice.
existing() { az "$1" account list -g "$BATCH_RG" --subscription "$SUB" --query "[0].name" -o tsv 2>/dev/null || true; }
newname() { echo "$PREFIX$1$(head -c 64 /dev/urandom | tr -dc 'a-z0-9' | head -c 8)"; }

end_date() { date -u -d "+$SECRET_HOURS hours" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
             || date -u -v+"$SECRET_HOURS"H +%Y-%m-%dT%H:%M:%SZ; }   # GNU or BSD date

write_env() {   # app id, secret, batch account
    umask 077
    cat > "$ENV_FILE" <<ENV
AZURE_CLIENT_ID=$1
AZURE_CLIENT_SECRET=$2
AZURE_TENANT_ID=$TENANT
AZURE_SUBSCRIPTION_ID=$SUB
BATCH_ACCOUNT=$3
BATCH_RG=$BATCH_RG
ENV
    chmod 600 "$ENV_FILE"
    say "wrote $ENV_FILE (mode 600; secret valid until $(end_date) UTC)"
}

issue_secret() {   # app id -> prints a fresh password; replaces any earlier secret
    az ad app credential reset --id "$1" --end-date "$(end_date)" --display-name climber \
        --query password -o tsv --only-show-errors
}

cmd_up() {
    sub
    say "subscription $SUB, region $LOCATION, group $BATCH_RG"
    az provider register -n Microsoft.Batch --subscription "$SUB" -o none --wait
    az group create -n "$BATCH_RG" -l "$LOCATION" --subscription "$SUB" -o none

    local SA BA
    SA=$(existing storage); SA=${SA:-$(newname st)}
    az storage account create -n "$SA" -g "$BATCH_RG" -l "$LOCATION" --subscription "$SUB" \
        --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
        --allow-blob-public-access false -o none
    say "storage account $SA"

    BA=$(existing batch); BA=${BA:-$(newname)}
    if ! az batch account show -n "$BA" -g "$BATCH_RG" --subscription "$SUB" -o none 2>/dev/null; then
        az batch account create -n "$BA" -g "$BATCH_RG" -l "$LOCATION" --subscription "$SUB" \
            --storage-account "$SA" -o none
    fi
    say "Batch account $BA"

    local SCOPE APP
    SCOPE=$(az group show -n "$BATCH_RG" --subscription "$SUB" --query id -o tsv)
    APP=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" -o tsv --only-show-errors)
    if [ -z "$APP" ]; then
        APP=$(az ad sp create-for-rbac --name "$SP_NAME" --role Contributor --scopes "$SCOPE" \
              --query appId -o tsv --only-show-errors)
    else
        az role assignment create --assignee "$APP" --role Contributor --scope "$SCOPE" \
            -o none --only-show-errors 2>/dev/null || true
    fi
    say "service principal $SP_NAME: Contributor on $BATCH_RG only"
    write_env "$APP" "$(issue_secret "$APP")" "$BA"
    quota "$BA"
    cat <<NEXT

Next:
  1. Put the lines of $ENV_FILE into the environment settings of the session that will run the
     climber (for a Claude Code cloud environment: its environment variables), then delete the
     file or keep it somewhere private.
  2. Allow these hosts in that environment's network settings:
       management.azure.com  login.microsoftonline.com  *.batch.azure.com  *.blob.core.windows.net
  3. Check it: $0 check
  4. Before each run: $0 rotate   (a fresh $SECRET_HOURS-hour secret)
NEXT
}

quota() {   # warn when the account can't run the pools a climb needs
    local LP
    LP=$(az batch account show -n "$1" -g "$BATCH_RG" --subscription "$SUB" \
         --query lowPriorityCoreQuota -o tsv 2>/dev/null || echo 0)
    if [ "${LP:-0}" -lt "$SPOT_VCPUS" ]; then
        cat <<Q
!! The Batch account has ${LP:-0} Spot vCPUs; a climb wants about $SPOT_VCPUS (four 16-vCPU nodes).
   New accounts often start low. Ask for more in the portal: the Batch account, then Quotas,
   then Request quota increase (Spot/low-priority vCPUs). It is free and usually quick.
Q
    else
        say "Spot quota: $LP vCPUs"
    fi
}

cmd_rotate() {
    sub
    local APP BA
    APP=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" -o tsv --only-show-errors)
    [ -n "$APP" ] || die "no service principal $SP_NAME; run up first"
    BA=$(existing batch); [ -n "$BA" ] || die "no Batch account in $BATCH_RG; run up first"
    write_env "$APP" "$(issue_secret "$APP")" "$BA"
}

cmd_check() {
    [ -f "$ENV_FILE" ] || die "no $ENV_FILE; run up first"
    set -a; . "$ENV_FILE"; set +a
    local CFG; CFG=$(mktemp -d)   # log in as the principal without touching your own login
    AZURE_CONFIG_DIR=$CFG az login --service-principal -u "$AZURE_CLIENT_ID" \
        -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" -o none --only-show-errors
    AZURE_CONFIG_DIR=$CFG az batch account login -n "$BATCH_ACCOUNT" -g "$BATCH_RG" \
        --subscription "$AZURE_SUBSCRIPTION_ID" --shared-key-auth -o none
    AZURE_CONFIG_DIR=$CFG az batch pool list -o table
    if AZURE_CONFIG_DIR=$CFG az group create -n "$BATCH_RG-scope-test" -l "${LOCATION}" \
           --subscription "$AZURE_SUBSCRIPTION_ID" -o none 2>/dev/null; then
        AZURE_CONFIG_DIR=$CFG az group delete -n "$BATCH_RG-scope-test" --yes --no-wait \
            --subscription "$AZURE_SUBSCRIPTION_ID"
        rm -rf "$CFG"; die "the principal could create a resource group outside $BATCH_RG: its scope is too wide"
    fi
    rm -rf "$CFG"
    say "ok: the principal reaches the Batch account and nothing outside $BATCH_RG"
}

cmd_down() {
    sub
    say "this deletes $BATCH_RG (every pool, job and stored output in it) and $SP_NAME"
    read -r -p "type the group name to confirm: " A
    [ "$A" = "$BATCH_RG" ] || die "not confirmed"
    local APP; APP=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" -o tsv --only-show-errors)
    [ -n "$APP" ] && az ad app delete --id "$APP" --only-show-errors
    az group delete -n "$BATCH_RG" --subscription "$SUB" --yes
    [ -f "$ENV_FILE" ] && rm -f "$ENV_FILE"
    say "deleted"
}

case "$CMD" in
    up) cmd_up ;; rotate) cmd_rotate ;; check) cmd_check ;; down) cmd_down ;;
    *) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
