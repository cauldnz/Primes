set pagination off
set confirm off
set print frame-arguments none
set print thread-events off
break *(fai_array_push+274)
commands
silent
continue
end
break *(fai_array_set+281)
commands
silent
continue
end
break *(fai_array_set+440)
commands
silent
continue
end
break fai_array_with_capacity
commands
silent
continue
end
break fai_array_repeat
commands
silent
continue
end
break fai2__x50rimes__start_x53ieve
commands
silent
continue
end
break _ZN11fai_runtime9alloc_obj17hf63fe519f720ca3dE
commands
silent
bt 2
continue
end
run > <scratch>/gp.prog.txt
info breakpoints
quit
