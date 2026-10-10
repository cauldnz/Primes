   8bce7:	mov    %r14,%rcx
   8bcea:	imul   %r14,%rcx
   8bcee:	jo     8c78a <$s15PrimeSieveSwift0aB0C03runB0yyF+0xbca>
   8bcf4:	add    $0xfffffffffffffffd,%rcx
   8bcf8:	jo     8c78c <$s15PrimeSieveSwift0aB0C03runB0yyF+0xbcc>
   8bcfe:	mov    %rcx,%rax
   8bd01:	shr    $0x3f,%rax
   8bd05:	add    %rcx,%rax
   8bd08:	sar    $1,%rax
   8bd0b:	mov    %r14d,%ecx
   8bd0e:	and    $0x7,%ecx
   8bd11:	mov    %eax,%esi
   8bd13:	and    $0x7,%esi
   8bd16:	mov    %rsi,%r8
   8bd19:	add    %r14,%r8
   8bd1c:	seto   %dl
   8bd1f:	cmp    $0x5,%rcx
   8bd23:	mov    %rsi,-0x58(%rbp)
   8bd27:	je     8c1b9 <$s15PrimeSieveSwift0aB0C03runB0yyF+0x5f9>
   8bd2d:	cmp    $0x3,%ecx
   8bd30:	je     8bf7a <$s15PrimeSieveSwift0aB0C03runB0yyF+0x3ba>
   8bd36:	cmp    $0x1,%ecx
   8bd39:	jne    8c3f9 <$s15PrimeSieveSwift0aB0C03runB0yyF+0x839>
   8bd3f:	test   %dl,%dl
   8bd41:	jne    8c792 <$s15PrimeSieveSwift0aB0C03runB0yyF+0xbd2>
   8bd47:	lea    (%r14,%r14,1),%rdx
   8bd4b:	mov    %rsi,%rdi
   8bd4e:	add    %rdx,%rdi
   8bd51:	jo     8c79c <$s15PrimeSieveSwift0aB0C03runB0yyF+0xbdc>
   8bd57:	lea    (%r14,%r14,2),%r15
   8bd5b:	add    %rsi,%r15
   8bd5e:	jo     8c7a4 <$s15PrimeSieveSwift0aB0C03runB0yyF+0xbe4>
   8bd64:	lea    0x0(,%r14,4),%rcx
   8bd6c:	add    %rsi,%rcx
   8bd6f:	jo     8c7aa <$s15PrimeSieveSwift0aB0C03runB0yyF+0xbea>
   8bd75:	lea    (%r14,%r14,4),%r12
   8bd79:	add    %rsi,%r12
   8bd7c:	jo     8c7b4 <$s15PrimeSieveSwift0aB0C03runB0yyF+0xbf4>
   8bd82:	lea    (%rdx,%rdx,2),%r9
   8bd86:	add    %rsi,%r9
   8bd89:	jo     8c7b6 <$s15PrimeSieveSwift0aB0C03runB0yyF+0xbf6>
   8bd8f:	imul   $0x7,%r14,%r13
   8bd93:	jo     8c7c0 <$s15PrimeSieveSwift0aB0C03runB0yyF+0xc00>
   8bd99:	add    %rsi,%r13
   8bd9c:	jo     8c7c8 <$s15PrimeSieveSwift0aB0C03runB0yyF+0xc08>
   8bda2:	sar    $0x3,%r13
   8bda6:	mov    -0xd8(%rbp),%r10
   8bdad:	sub    %r13,%r10
   8bdb0:	jo     8c7d2 <$s15PrimeSieveSwift0aB0C03runB0yyF+0xc12>
   8bdb6:	mov    %r10,%r11
   8bdb9:	sub    %r14,%r11
   8bdbc:	jo     8c7d8 <$s15PrimeSieveSwift0aB0C03runB0yyF+0xc18>
   8bdc2:	mov    %r10,-0x90(%rbp)
   8bdc9:	sar    $0x3,%r8
   8bdcd:	sar    $0x3,%rdi
   8bdd1:	sar    $0x3,%r15
   8bdd5:	sar    $0x3,%rcx
   8bdd9:	sar    $0x3,%r12
   8bddd:	sar    $0x3,%r9
   8bde1:	sar    $0x3,%rax
   8bde5:	cmp    %r11,%rax
   8bde8:	mov    %r8,-0x98(%rbp)
   8bdef:	mov    %rdi,-0x88(%rbp)
   8bdf6:	mov    %r15,-0x80(%rbp)
   8bdfa:	mov    %rcx,-0x78(%rbp)
   8bdfe:	mov    %r12,-0x70(%rbp)
   8be02:	mov    %r9,-0x68(%rbp)
   8be06:	mov    %r13,-0x60(%rbp)
   8be0a:	jge    8bf17 <$s15PrimeSieveSwift0aB0C03runB0yyF+0x357>
   8be10:	lea    (%rbx,%r14,1),%rsi
   8be14:	mov    %rsi,-0xd0(%rbp)
   8be1b:	lea    (%r14,%r8,1),%rsi
   8be1f:	add    %rbx,%rsi
   8be22:	mov    %rsi,-0xc8(%rbp)
   8be29:	lea    (%r14,%rdi,1),%rsi
   8be2d:	add    %rbx,%rsi
   8be30:	mov    %rsi,-0xc0(%rbp)
   8be37:	lea    (%r14,%r15,1),%rsi
   8be3b:	add    %rbx,%rsi
   8be3e:	mov    %rsi,-0xb8(%rbp)
   8be45:	lea    (%r14,%rcx,1),%rsi
   8be49:	add    %rbx,%rsi
   8be4c:	mov    %rsi,-0xb0(%rbp)
   8be53:	mov    %r11,-0xa8(%rbp)
   8be5a:	lea    (%r14,%r12,1),%rsi
   8be5e:	add    %rbx,%rsi
   8be61:	mov    %rsi,-0xa0(%rbp)
   8be68:	mov    %rcx,%rsi
   8be6b:	lea    (%r14,%r9,1),%rcx
   8be6f:	add    %rbx,%rcx
   8be72:	lea    (%r14,%r13,1),%r10
   8be76:	add    %rbx,%r10
   8be79:	add    %rbx,%r13
   8be7c:	add    %rbx,%r9
   8be7f:	add    %rbx,%r12
   8be82:	add    %rbx,%rsi
   8be85:	add    %rbx,%r15
   8be88:	add    %rbx,%rdi
   8be8b:	add    %rbx,%r8
   8be8e:	xchg   %ax,%ax
   8be90:	orb    $0x80,(%rbx,%rax,1)
   8be94:	orb    $0x1,(%r8,%rax,1)
   8be99:	orb    $0x2,(%rdi,%rax,1)
   8be9d:	orb    $0x4,(%r15,%rax,1)
   8bea2:	orb    $0x8,(%rsi,%rax,1)
   8bea6:	orb    $0x10,(%r12,%rax,1)
   8beab:	orb    $0x20,(%r9,%rax,1)
   8beb0:	orb    $0x40,0x0(%r13,%rax,1)
   8beb6:	mov    -0xd0(%rbp),%r11
   8bebd:	orb    $0x80,(%r11,%rax,1)
   8bec2:	mov    -0xc8(%rbp),%r11
   8bec9:	orb    $0x1,(%r11,%rax,1)
   8bece:	mov    -0xc0(%rbp),%r11
   8bed5:	orb    $0x2,(%r11,%rax,1)
   8beda:	mov    -0xb8(%rbp),%r11
   8bee1:	orb    $0x4,(%r11,%rax,1)
   8bee6:	mov    -0xb0(%rbp),%r11
   8beed:	orb    $0x8,(%r11,%rax,1)
   8bef2:	mov    -0xa0(%rbp),%r11
   8bef9:	orb    $0x10,(%r11,%rax,1)
   8befe:	orb    $0x20,(%rcx,%rax,1)
   8bf02:	orb    $0x40,(%r10,%rax,1)
   8bf07:	add    %rdx,%rax
   8bf0a:	cmp    -0xa8(%rbp),%rax
   8bf11:	jl     8be90 <$s15PrimeSieveSwift0aB0C03runB0yyF+0x2d0>
   8bf17:	cmp    -0x90(%rbp),%rax
   8bf1e:	jge    8c6d0 <$s15PrimeSieveSwift0aB0C03runB0yyF+0xb10>
   8bf24:	mov    -0x48(%rbp),%rbx
   8bf28:	orb    $0x80,(%rbx,%rax,1)
   8bf2c:	lea    (%rbx,%rax,1),%rcx
   8bf30:	mov    -0x98(%rbp),%rdx
   8bf37:	orb    $0x1,(%rdx,%rcx,1)
   8bf3b:	mov    -0x88(%rbp),%rdx
   8bf42:	orb    $0x2,(%rdx,%rcx,1)
   8bf46:	mov    -0x80(%rbp),%rdx
   8bf4a:	orb    $0x4,(%rdx,%rcx,1)
   8bf4e:	mov    -0x78(%rbp),%rdx
   8bf52:	orb    $0x8,(%rdx,%rcx,1)
   8bf56:	mov    -0x70(%rbp),%rdx
   8bf5a:	orb    $0x10,(%rdx,%rcx,1)
   8bf5e:	mov    -0x68(%rbp),%rdx
   8bf62:	orb    $0x20,(%rdx,%rcx,1)
   8bf66:	mov    -0x60(%rbp),%rdx
   8bf6a:	orb    $0x40,(%rdx,%rcx,1)
   8bf6e:	add    %r14,%rax
   8bf71:	mov    -0x50(%rbp),%r13
   8bf75:	jmp    8c6d8 <$s15PrimeSieveSwift0aB0C03runB0yyF+0xb18>
