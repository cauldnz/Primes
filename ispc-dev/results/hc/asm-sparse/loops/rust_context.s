   39c79:	mov    %edi,%eax
   39c7b:	xor    %edx,%edx
   39c7d:	div    %r8d
   39c80:	sub    %rdx,%rdi
   39c83:	mov    0x20(%rsp),%r9
   39c88:	sub    %rdi,%r9
   39c8b:	jb     3aeae <prime_sieve_rust::run_implementation_st+0x1a3e>
   39c91:	lea    0x0(,%r8,8),%r10
   39c99:	mov    %rsi,%r13
   39c9c:	movabs $0x7fffffffffffffff,%rax
   39ca6:	and    %rax,%r13
   39ca9:	sub    %r8,%r10
   39cac:	shr    $0x3,%rsi
   39cb0:	lea    (%r8,%r13,1),%r14
   39cb4:	lea    (%r8,%r8,2),%rbx
   39cb8:	lea    (%rbx,%r13,1),%r15
   39cbc:	lea    (%r8,%r8,4),%r11
   39cc0:	add    %r13,%r11
   39cc3:	add    %r13,%r10
   39cc6:	mov    %r9,%rax
   39cc9:	or     %r8,%rax
   39ccc:	shr    $0x20,%rax
   39cd0:	je     3a4df <prime_sieve_rust::run_implementation_st+0x106f>
   39cd6:	mov    %r9,%rax
   39cd9:	xor    %edx,%edx
   39cdb:	div    %r8
   39cde:	jmp    3a4e7 <prime_sieve_rust::run_implementation_st+0x1077>
   39ce3:	mov    %r9d,%eax
   39ce6:	xor    %edx,%edx
   39ce8:	div    %r8d
   39ceb:	movabs $0xfffffffffffffff,%rax
   39cf5:	and    %rax,%rsi
   39cf8:	shr    $0x3,%r14
   39cfc:	lea    0x0(,%r8,2),%rcx
   39d04:	add    %r13,%rcx
   39d07:	shr    $0x3,%rcx
   39d0b:	shr    $0x3,%r15
   39d0f:	lea    0x0(,%r8,4),%rbp
   39d17:	add    %r13,%rbp
   39d1a:	shr    $0x3,%rbp
   39d1e:	shr    $0x3,%r11
   39d22:	lea    0x0(%r13,%rbx,2),%r13
   39d27:	shr    $0x3,%r13
   39d2b:	shr    $0x3,%r10
   39d2f:	add    0x10(%rsp),%rdi
   39d34:	sub    %rdx,%r9
   39d37:	cmp    %r8,%r9
   39d3a:	jb     39d80 <prime_sieve_rust::run_implementation_st+0x910>
   39d3c:	mov    %rdi,%rax
   39d3f:	mov    %r9,%rbx
   39d42:	cs nopw 0x0(%rax,%rax,1)
   39d4c:	nopl   0x0(%rax)
   39d50:	orb    $0x10,(%rax,%rsi,1)
   39d54:	orb    $0x20,(%rax,%r14,1)
   39d59:	orb    $0x40,(%rax,%rcx,1)
   39d5d:	orb    $0x80,(%rax,%r15,1)
   39d62:	orb    $0x1,(%rax,%rbp,1)
   39d66:	orb    $0x2,(%rax,%r11,1)
   39d6b:	orb    $0x4,(%rax,%r13,1)
   39d70:	orb    $0x8,(%rax,%r10,1)
   39d75:	add    %r8,%rax
   39d78:	sub    %r8,%rbx
   39d7b:	cmp    %r8,%rbx
   39d7e:	jae    39d50 <prime_sieve_rust::run_implementation_st+0x8e0>
   39d80:	cmp    %rdx,%rsi
   39d83:	mov    0x28(%rsp),%rbx
   39d88:	jae    39710 <prime_sieve_rust::run_implementation_st+0x2a0>
   39d8e:	add    %r9,%rsi
   39d91:	orb    $0x10,(%rdi,%rsi,1)
   39d95:	cmp    %rdx,%r14
   39d98:	jae    39710 <prime_sieve_rust::run_implementation_st+0x2a0>
   39d9e:	add    %r9,%r14
   39da1:	orb    $0x20,(%rdi,%r14,1)
   39da6:	cmp    %rdx,%rcx
   39da9:	jae    39710 <prime_sieve_rust::run_implementation_st+0x2a0>
   39daf:	add    %r9,%rcx
   39db2:	orb    $0x40,(%rdi,%rcx,1)
   39db6:	cmp    %rdx,%r15
   39db9:	jae    39710 <prime_sieve_rust::run_implementation_st+0x2a0>
   39dbf:	add    %r9,%r15
   39dc2:	orb    $0x80,(%rdi,%r15,1)
   39dc7:	cmp    %rdx,%rbp
   39dca:	jae    39710 <prime_sieve_rust::run_implementation_st+0x2a0>
   39dd0:	add    %r9,%rbp
   39dd3:	orb    $0x1,(%rdi,%rbp,1)
   39dd7:	cmp    %rdx,%r11
   39dda:	jae    39710 <prime_sieve_rust::run_implementation_st+0x2a0>
   39de0:	add    %r9,%r11
   39de3:	orb    $0x2,(%rdi,%r11,1)
   39de8:	cmp    %rdx,%r13
   39deb:	jae    39710 <prime_sieve_rust::run_implementation_st+0x2a0>
   39df1:	add    %r9,%r13
   39df4:	orb    $0x4,(%rdi,%r13,1)
   39df9:	cmp    %rdx,%r10
   39dfc:	jae    39710 <prime_sieve_rust::run_implementation_st+0x2a0>
   39e02:	add    %r10,%r9
   39e05:	orb    $0x8,(%rdi,%r9,1)
   39e0a:	jmp    39710 <prime_sieve_rust::run_implementation_st+0x2a0>
