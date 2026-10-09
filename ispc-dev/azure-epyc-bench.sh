#!/usr/bin/env bash
# Benchmark the ISPC Primes solution against the current leaders on Azure AMD EPYC VMs.
# Not part of the submission. Untested as a whole: written in a sandbox without Azure access.
#
# Usage:  ./azure-epyc-bench.sh [vm-size ...]
#   default sizes: Standard_D32as_v5 (EPYC Zen 3, AVX2 only)
#                  Standard_D32as_v6 (EPYC Zen 4, AVX-512)
# Requires: az CLI logged in, ssh. Run from anywhere; uses ../PrimeISPC/solution_1.
# Every VM lives in one resource group that is deleted at the end (also on Ctrl-C).
set -euo pipefail

LOCATION="${LOCATION:-australiaeast}"
RG="${RG:-primes-bench-$(date +%Y%m%d%H%M)}"
SIZES=("${@:-Standard_D32as_v5 Standard_D32as_v6}")
read -r -a SIZES <<< "${SIZES[*]}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SOLUTION="$HERE/../PrimeISPC/solution_1"
OUT="$HERE/results/azure-$(date +%Y%m%d%H%M)"
mkdir -p "$OUT"

cleanup() { echo "Deleting resource group $RG"; az group delete -n "$RG" --yes --no-wait || true; }
trap cleanup EXIT

az group create -n "$RG" -l "$LOCATION" -o none

# Runs on each VM: install Docker, fetch upstream drag-race branch, drop in our solution,
# build ours and the leaders, run everything, sweep the dense threshold.
REMOTE_SCRIPT='
set -e
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq && sudo apt-get install -y -qq docker.io git >/dev/null
sudo usermod -aG docker "$USER"
lscpu | grep -E "Model name|^CPU\(s\)|avx512f" | sed "s/Flags:.*avx512f.*/AVX-512: yes/"
git clone -q --depth 1 -b drag-race https://github.com/PlummersSoftwareLLC/Primes.git
mkdir -p Primes/PrimeISPC && cp -r ~/solution_1 Primes/PrimeISPC/
cd Primes
build() { sudo docker build -q -t "$2" "$1" >/dev/null; }
build PrimeISPC/solution_1 ispc
build PrimeC/solution_5 c5
build PrimeC/solution_2 c2
build PrimeRust/solution_1 r1
echo "== self-test";      sudo docker run --rm -e PRIMES_TEST=1 ispc
for i in 1 2 3; do
  echo "== round $i ISPC";  sudo docker run --rm ispc
  echo "== round $i C5";    sudo docker run --rm c5
done
echo "== C2";   sudo docker run --rm c2   | grep -E "5760of30030|480of2310"
echo "== Rust"; sudo docker run --rm r1   | sort -t";" -k2 -nr | head -4
for d in 128 192 256 320 384 448 512 640; do
  echo "== DENSE_MAX=$d"; sudo docker run --rm -e PRIMES_DENSE_MAX=$d ispc
done
'

for SIZE in "${SIZES[@]}"; do
  VM="primes-${SIZE//_/-}"; VM="${VM,,}"; VM="${VM:0:40}"
  echo "### $SIZE"
  az vm create -g "$RG" -n "$VM" --image Ubuntu2404 --size "$SIZE" \
     --admin-username azureuser --generate-ssh-keys --public-ip-sku Standard -o none
  IP=$(az vm show -d -g "$RG" -n "$VM" --query publicIps -o tsv)
  SSH="ssh -o StrictHostKeyChecking=accept-new azureuser@$IP"
  scp -o StrictHostKeyChecking=accept-new -r "$SOLUTION" "azureuser@$IP:~/"
  $SSH "bash -s" <<< "$REMOTE_SCRIPT" | tee "$OUT/$SIZE.txt"
  az vm delete -g "$RG" -n "$VM" --yes -o none   # stop paying for it as soon as it's done
done

echo "Results in $OUT"
