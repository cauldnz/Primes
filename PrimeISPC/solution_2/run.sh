#!/bin/sh
# Diagnostic only (never merged): how much of the drop at scale is clock speed? One sieve
# thread, ours and Rust, pinned to cpu0 while other CPUs run busy work: none; cpu0's SMT
# sibling only; one thread on each of 16 other cores; one on every other core; every other
# vCPU. Busy work is an integer spin loop, then (as a realistic load) Rust's sieve.
if [ -n "$PRIMES_TEST" ]; then exec ./primes; fi
N=$(nproc)
lscpu | grep -E "Model name|Thread\(s\) per core|Core\(s\) per socket" | sed 's/  */ /g; s/^/diag;lscpu;/'
first() { sed 's/[,-].*//' "/sys/devices/system/cpu/cpu$1/topology/thread_siblings_list"; }
SIB=""; PRIM=""; ALL=""
c=1; while [ "$c" -lt "$N" ]; do
  f=$(first "$c")
  if [ "$f" = "$(first 0)" ]; then SIB="$c"; fi
  if [ "$f" = "$c" ] && [ "$f" != "$(first 0)" ]; then PRIM="$PRIM $c"; fi
  ALL="$ALL $c"; c=$((c + 1)); done
P16=$(echo $PRIM | tr ' ' '\n' | head -16 | tr '\n' ' ')
echo "diag;sets;sib=$SIB;cores=$(echo $PRIM | wc -w);all=$(echo $ALL | wc -w)"
spin() { for c in $1; do taskset -c "$c" sh -c 'while :; do :; done' & done; }
sieveload() { [ -n "$1" ] && taskset -c "$(echo $1 | tr ' ' ',')" ./prime-sieve-rust --bits-extreme -t "$(echo $1 | wc -w)" -d 40 >/dev/null 2>&1 & }
measure() {  # $1 label
  sleep 2
  taskset -c 0 ./primes | grep ";1;" | sed "s/^cauldnz-ispc-base/ours-$1/"
  taskset -c 0 ./prime-sieve-rust --bits-extreme -t 1 2>/dev/null | grep "^mike" | sed "s/^mike-barber_bit-extreme-hybrid/rust-$1/"
}
stop() { pkill -f 'while :; do :; done' 2>/dev/null; pkill -f 'prime-sieve-rust --bits-extreme -t [0-9]* -d 40' 2>/dev/null; wait 2>/dev/null; sleep 1; }
measure idle
for kind in spin sieve; do
  for set in sib c16 cores all; do
    case $set in sib) S="$SIB";; c16) S="$P16";; cores) S="$PRIM";; all) S="$ALL";; esac
    [ -z "$S" ] && continue
    if [ $kind = spin ]; then spin "$S"; else sieveload "$S"; sleep 6; fi
    measure "$kind-$set-$(echo $S | wc -w)"
    stop
  done
done
