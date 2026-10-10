#!/bin/sh
# DIAGNOSTIC (hc/diag-asm-wheel): print the disassembly of the hot functions of two wheel
# sieves built on this node: the ISPC wheel (PrimeISPC/solution_1) and the Zig wheel
# (PrimeZig/solution_4). Every output line is prefixed "asm;<entry>;" (or "asm;meta;") so a
# harness keeping only lines that contain ';' keeps all of it. The last line is "asm;done".
#
# PRIMES_TEST=1 runs the ISPC wheel's own self-test (sizes 10 to 10^8) and exits with its code.

if [ -n "${PRIMES_TEST:-}" ] && [ "$PRIMES_TEST" != "0" ]; then
    exec "${ISPC_BIN:-$(dirname "$0")/ispc-primes}"
fi

CAP=${ASM_CAP:-40000}
DIR=$(dirname "$0")
ISPC_BIN=${ISPC_BIN:-$DIR/ispc-primes}
ZIG_BIN=${ZIG_BIN:-$DIR/zig-primes}            # the submission binary (stripped)
ZIG_SYM=${ZIG_SYM:-$DIR/zig-primes-sym}        # same flags without -fstrip
TMP=${TMPDIR:-/tmp}/asm.$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

# ---- meta: machine, toolchains, symbol tables -------------------------------------------
meta() { sed "s/^/asm;meta;$1;/"; }
grep -m1 'model name' /proc/cpuinfo | meta cpu
echo "nproc $(nproc 2>/dev/null)" | meta cpu
flags=$(grep -m1 '^flags' /proc/cpuinfo)
echo "$(echo "$flags" | tr ' ' '\n' | grep -E '^(avx|avx2|bmi2|avx512[a-z_]*|movdir.*|fsrm|erms)$' |
    tr '\n' ' ')" | meta cpu-flags
isa=sse4
case " $flags " in *" avx2 "*) isa=avx2 ;; esac
for f in avx512f avx512dq avx512cd avx512bw avx512vl; do
    case " $flags " in *" $f "*) ;; *) f=missing; break ;; esac
done
[ "$f" != missing ] && isa=avx512skx
echo "ispc dispatch expected: $isa (from /proc/cpuinfo flags)" | meta cpu
[ -f "$DIR/ispc-version.txt" ] && meta ispc-version < "$DIR/ispc-version.txt"
[ -f "$DIR/zig-version.txt" ] && meta zig-version < "$DIR/zig-version.txt"
if [ -f "$DIR/zig-native.txt" ]; then
    grep -m1 '"name"' "$DIR/zig-native.txt" | tr -d ' ",' | meta zig-native-cpu
    awk '/"features"/{f=1;next} f&&/\]/{exit} f{gsub(/[ ",]/,""); printf "%s ", $0} END{print ""}' \
        "$DIR/zig-native.txt" | meta zig-native-features
fi
for b in "$ISPC_BIN" "$ZIG_SYM"; do
    e=$(basename "$b")
    [ -f "$b" ] || { echo "!! $b missing" | meta "nm;$e"; continue; }
    size -A "$b" | grep -E '^\.text' | meta "size;$e"
    nm -S --size-sort --defined-only "$b" | meta "nm;$e"
done
[ -f "$ZIG_BIN" ] && size -A "$ZIG_BIN" | grep -E '^\.text' | meta "size;zig-primes(stripped)"

# ---- dump <entry> <binary> <exclude-regex> <pattern>... ---------------------------------
# Patterns are extended regexes matched against demangled names (nm -C), tried in order;
# names matching the exclude regex are skipped. Symbols are ordered by ISA (avx512 first, then
# avx2, then the rest), then by the first pattern they match. Each symbol is disassembled by
# address range, so static functions with the same name are all handled.
dump() {
    entry=$1; bin=$2; excl=$3; shift 3
    if [ ! -f "$bin" ]; then
        echo "asm;$entry;!! binary $bin missing"
        return
    fi
    pats=$(printf '%s\n' "$@")
    nm -C -S --defined-only "$bin" 2>/dev/null | awk -v pats="$pats" -v excl="$excl" '
        BEGIN { n = split(pats, P, "\n") }
        NF >= 4 && ($3 == "t" || $3 == "T" || $3 == "W" || $3 == "w") {
            name = $4; for (i = 5; i <= NF; i++) name = name " " $i
            if (excl != "" && name ~ excl) next
            for (i = 1; i <= n; i++) if (P[i] != "" && name ~ P[i]) break
            if (i > n) next
            isa = (name ~ /avx512/) ? 0 : (name ~ /avx2/) ? 1 : 2
            if ($2 ~ /^0+$/) next
            printf "%d %04d %s %s %s\n", isa, i, $2, $1, name
        }' | sort -k1,1n -k2,2n -k3,3 | awk '!seen[$4]++' > "$TMP/$entry.list"
    if [ ! -s "$TMP/$entry.list" ]; then
        echo "asm;$entry;!! no symbol matched"
        return
    fi
    while read -r isa idx hsize addr name; do
        echo "asm;$entry;## selected 0x$hsize bytes: $name"
    done < "$TMP/$entry.list"
    lines=0
    while read -r isa idx hsize addr name; do
        if [ "$lines" -ge "$CAP" ]; then
            echo "asm;$entry;!! cap of $CAP lines reached, skipping $name"
            continue
        fi
        start=$((0x$addr)); stop=$((0x$addr + 0x$hsize))
        echo "asm;$entry;== $name"
        objdump -d --no-show-raw-insn -M att -C --start-address="$start" --stop-address="$stop" "$bin" |
            sed -e '1,/^Disassembly of section/d' -e '/^$/d' | head -n $((CAP - lines)) > "$TMP/fn.s"
        sed "s/^/asm;$entry;/" "$TMP/fn.s"
        lines=$((lines + $(wc -l < "$TMP/fn.s")))
        if [ -n "${STRIPPED:-}" ]; then strip_check "$entry" "$name"; fi
    done < "$TMP/$entry.list"
}

# Instruction text with addresses, branch targets and rip displacements blanked, one line.
norm() {
    grep -E '^ *[0-9a-f]+:'"$(printf '\t')" | sed -E -e 's/^ *[0-9a-f]+:\t//' -e 's/[[:space:]]*#.*$//' \
        -e 's/[[:space:]]+/ /g' -e 's/^(j[a-z]*|call|notrack jmp) .*/\1 T/' \
        -e 's/-?0x[0-9a-f]+\(%rip\)/X(%rip)/g' -e 's/0x[0-9a-f]{6,}/A/g' |
        tr '\n' '|'
}

# Does the function just dumped (TMP/fn.s) occur, instruction for instruction, in the
# stripped submission binary?
strip_check() {
    if [ ! -f "$TMP/stripped.norm" ]; then
        objdump -d --no-show-raw-insn -M att "$STRIPPED" | norm > "$TMP/stripped.norm"
    fi
    norm < "$TMP/fn.s" > "$TMP/fn.norm"
    if grep -qF -f "$TMP/fn.norm" "$TMP/stripped.norm"; then r=identical; else r=DIFFERENT; fi
    echo "asm;$1;## in stripped submission binary: $r ($2)"
}

dump ispc "$ISPC_BIN" '_sse4$' \
    'apply_group' 'sparse_prime' 'dense_primes' 'run_sieve' 'apply_range' 'build_group' \
    'build_pattern' 'start_bit'

STRIPPED=$ZIG_BIN dump zig "$ZIG_SYM" '' \
    'WheelSieve\.run$' 'WheelSieve\.densePrimes' 'WheelSieve\.sparsePrime' 'applyGroup' \
    'WheelSieve\.apply$' 'WheelSieve\.buildGroup' 'buildPattern' 'startBit' '^memcpy$' '^memset$'

echo "asm;done"
exit 0
