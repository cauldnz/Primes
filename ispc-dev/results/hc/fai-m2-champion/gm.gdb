set pagination off
set print frame-arguments none
break _ZN11fai_runtime10make_piece17h6dbec83cf0420dd4E
commands
silent
bt 5
continue
end
run > /dev/null
quit
