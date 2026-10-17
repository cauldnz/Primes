set pagination off
set confirm off
set print frame-arguments none
set environment PRIMES_TEST=1
break _ZN11fai_runtime9alloc_obj17hf63fe519f720ca3dE
commands
silent
bt 3
continue
end
break fai_array_set
commands
silent
printf "HIT fai_array_set\n"
bt 2
continue
end
run > <scratch>/g1.prog.txt
info breakpoints
quit
