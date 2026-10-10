.Lloop:
  orb    $0x10,(%rax,%rsi,1)
  orb    $0x20,(%rax,%r14,1)
  orb    $0x40,(%rax,%rcx,1)
  orb    $0x80,(%rax,%r15,1)
  orb    $0x1,(%rax,%rbp,1)
  orb    $0x2,(%rax,%r11,1)
  orb    $0x4,(%rax,%r13,1)
  orb    $0x8,(%rax,%r10,1)
  add    %r8,%rax
  sub    %r8,%rbx
  cmp    %r8,%rbx
  jae .Lloop
