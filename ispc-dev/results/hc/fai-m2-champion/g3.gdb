set pagination off
set confirm off
set environment PRIMES_TEST=1
break *(fai2__x50rimes__start_x53ieve+118)
commands
silent
continue
end
break *(fai2__x50rimes__start_x53ieve+168)
commands
silent
continue
end
break *(fai2__x50rimes__start_x53ieve+350)
commands
silent
continue
end
break *(fai2__x50rimes__push_x54hree+318)
commands
silent
continue
end
break *(fai2__x50rimes__push_x5aeros+211)
commands
silent
continue
end
break fai_array_push
commands
silent
continue
end
break fai_array_set
commands
silent
continue
end
break fai_alloc_array
commands
silent
continue
end
break fai_array_repeat
commands
silent
continue
end
break _ZN11fai_runtime9alloc_obj17hf63fe519f720ca3dE
commands
silent
continue
end
break fai2__x50rimes__start_x53ieve
commands
silent
continue
end
run > /dev/null
info breakpoints
quit
