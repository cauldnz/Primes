# usage: t3.sh label pre-cmd cmd ; runs 3 times, prints times and median
label=$1; pre=$2; cmd=$3; ts=""
for i in 1 2 3; do sh -c "$pre" >/dev/null 2>&1; a=$(date +%s.%N); sh -c "$cmd" >/dev/null 2>&1; rc=$?; b=$(date +%s.%N); ts="$ts $(echo "$b - $a" | bc)"; [ $rc = 0 ] || echo "  rc=$rc on run $i"; done
med=$(printf '%s\n' $ts | sort -n | sed -n 2p)
printf '%-40s runs:%s  median=%s\n' "$label" "$ts" "$med"
