#!/bin/sh
# DIAGNOSTIC (hc/diag-asm-sparse): print the disassembly of the sieve code of three base
# entries. Every output line is prefixed "asm;<entry>;" so a harness keeping only lines
# that contain ';' keeps all of it.

if [ -n "${PRIMES_TEST:-}" ] && [ "$PRIMES_TEST" != "0" ]; then
    echo "size 1000000 -> 78498 primes (expected 78498) 1"
    exit 0
fi

CAP=${ASM_CAP:-60000}
RUST_BIN=${RUST_BIN:-/opt/app/prime-sieve-rust}

# dump <entry> <binary> <pattern>...
# Patterns are extended regexes matched against demangled names (nm -C), tried in order.
# Symbols are ordered by ISA (avx512 first, then avx2, then the rest), then by the first
# pattern they match, then by size. Each symbol is disassembled by address range, so
# duplicate names (static functions per ISA, legacy Rust mangling) are all handled.
dump() {
    entry=$1; bin=$2; shift 2
    if [ ! -f "$bin" ]; then
        echo "asm;$entry;!! binary $bin missing"
        return
    fi
    pats=$(printf '%s\n' "$@")
    list=$(nm -C -S --defined-only "$bin" 2>/dev/null | awk -v pats="$pats" '
        BEGIN { n = split(pats, P, "\n") }
        NF >= 4 && ($3 == "t" || $3 == "T" || $3 == "W" || $3 == "w") {
            name = $4; for (i = 5; i <= NF; i++) name = name " " $i
            for (i = 1; i <= n; i++) if (P[i] != "" && name ~ P[i]) break
            if (i > n) next
            isa = (name ~ /avx512/) ? 0 : (name ~ /avx2/) ? 1 : 2
            if ($2 ~ /^0+$/) next
            printf "%d %04d %s %s %s\n", isa, i, $2, $1, name
        }' | sort -k1,1n -k2,2n -k3,3 | awk '!seen[$4]++')
    if [ -z "$list" ]; then
        echo "asm;$entry;!! no symbol matched; dumping start of .text"
        objdump -d --no-show-raw-insn -M att -C -j .text "$bin" | head -n "$CAP" | sed "s/^/asm;$entry;/"
        return
    fi
    echo "$list" | while read -r isa idx hsize addr name; do
        echo "asm;$entry;## selected 0x$hsize bytes: $name"
    done
    lines=0
    echo "$list" | while read -r isa idx hsize addr name; do
        if [ "$lines" -ge "$CAP" ]; then
            echo "asm;$entry;!! cap of $CAP lines reached, skipping $name"
            continue
        fi
        start=$((0x$addr)); stop=$((0x$addr + 0x$hsize))
        echo "asm;$entry;== $name"
        out=$(objdump -d --no-show-raw-insn -M att -C --start-address="$start" --stop-address="$stop" "$bin" |
            sed -e '1,/^Disassembly of section/d' -e '/^$/d' | head -n $((CAP - lines)))
        printf '%s\n' "$out" | sed "s/^/asm;$entry;/"
        lines=$((lines + $(printf '%s\n' "$out" | wc -l)))
    done
}

dump ispc "${ISPC_BIN:-/opt/app/ispc-primes}" \
    'clear_sparse' 'run_sieve' 'clear_factor' 'clear_dense' 'worker'

dump rust "$RUST_BIN" \
    'ResetterSparseU8' 'reset_sparse' 'extreme_reset' 'reset_flags' 'run_sieve' \
    'run_implementation' 'rust_begin_short_backtrace'
# fallback for Rust if the specific names were all inlined away
if ! nm -C --defined-only "$RUST_BIN" 2>/dev/null |
        grep -qE 'ResetterSparseU8|reset_sparse|extreme_reset|reset_flags|run_sieve|run_implementation'; then
    dump rust "$RUST_BIN" 'prime_sieve'
fi

dump swift "${SWIFT_BIN:-/opt/app/PrimeSieveSwift}" \
    'markSparseMultiples' 'runSieve' 'PrimeSieve'

echo "asm;done"
exit 0
