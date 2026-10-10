.Lloop:
  orb    $0x1,(%rsi,%r14,1)
  orb    $0x2,(%rsi,%r12,1)
  orb    $0x4,(%rsi,%r15,1)
  orb    $0x8,(%rsi,%rdx,1)
  orb    $0x10,(%rsi,%rbx,1)
  orb    $0x20,(%rsi,%rbp,1)
  orb    $0x40,(%rsi,%r8,1)
  orb    $0x80,(%rsi,%r10,1)
  mov    %rcx,%rsi
  add    %r13,%rcx
  cmp    %rax,%rcx
  jle .Lloop
