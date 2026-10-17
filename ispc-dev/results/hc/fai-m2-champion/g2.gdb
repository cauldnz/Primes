set pagination off
set confirm off
set print frame-arguments none
set environment PRIMES_TEST=1
break fai2__x50rimes__start_x53ieve
commands
silent
printf "START_SIEVE q=%ld nbits=%ld nwords=%ld\n", $rdi, $rsi, $rdx
continue
end
break fai_alloc_array
commands
silent
printf "ALLOC_ARRAY cap=%ld\n", $rdi
continue
end
break fai_array_repeat
commands
silent
printf "REPEAT %ld %ld\n", $rdi, $rsi
continue
end
run > /dev/null
quit
