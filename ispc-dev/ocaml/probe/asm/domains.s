	.file ""
	.section .rodata.cst16,"aM",@progbits,16
	.align	16
caml_negf_mask:
	.8byte	0x8000000000000000
	.8byte	0
	.align	16
caml_absf_mask:
	.8byte	0x7fffffffffffffff
	.8byte	-1
caml_negf32_mask:
	.8byte	0x80000000
	.8byte	0
	.align	16
caml_absf32_mask:
	.8byte	0xffffffff7fffffff
	.8byte	-1
	.data
	.globl	camlDomains__data_begin
camlDomains__data_begin:
	.text
	.globl	camlDomains__code_begin
camlDomains__code_begin:
.Lcaml_call_gc_:
	.cfi_startproc
	jmp	caml_call_gc@PLT
	.cfi_endproc
.Lcaml_call_gc_sse_:
	.cfi_startproc
	jmp	caml_call_gc_sse@PLT
	.cfi_endproc
.Lcaml_call_gc_avx_:
	.cfi_startproc
	jmp	caml_call_gc_avx@PLT
	.cfi_endproc
.Lcaml_call_gc_avx512_:
	.cfi_startproc
	jmp	caml_call_gc_avx512@PLT
	.cfi_endproc
	.data
	.align	8
	.globl	camlDomains__gc_roots
camlDomains__gc_roots:
.LcamlDomains__gc_roots:
	.8byte	0
	.data
	.align	8
	.8byte	3063
.LcamlDomains__fn$5bdomains.ml$3a49$2c23$2d$2d97$5d_11:
	.8byte	.LcamlDomains__fn$5bdomains.ml$3a49$2c23$2d$2d97$5d_5_15_code
	.8byte	0x180000000000005
	.data
	.align	8
	.8byte	3063
.LcamlDomains__fn$5bdomains.ml$3a43$2c23$2d$2d129$5d_9:
	.8byte	.LcamlDomains__fn$5bdomains.ml$3a43$2c23$2d$2d129$5d_3_10_code
	.8byte	0x180000000000005
	.data
	.align	8
	.8byte	4864
	.globl	camlDomains
camlDomains:
.LcamlDomains:
	.8byte	2000001
	.8byte	1000001
	.8byte	camlDomains__sieve_7
	.8byte	camlDomains__passes_8
	.data
	.align	8
	.8byte	3063
	.globl	camlDomains__passes_8
camlDomains__passes_8:
.LcamlDomains__passes_8:
	.8byte	camlDomains__passes_2_9_code
	.8byte	0x180000000000005
	.data
	.align	8
	.8byte	3063
	.globl	camlDomains__sieve_7
camlDomains__sieve_7:
.LcamlDomains__sieve_7:
	.8byte	camlDomains__sieve_0_7_code
	.8byte	0x180000000000005
	.data
	.align	8
	.8byte	2827
.LcamlDomains__const_block208:
	.8byte	.LcamlDomains__immstring202
	.8byte	.LcamlDomains__const_block206
	.data
	.align	8
	.8byte	4868
.LcamlDomains__const_block206:
	.8byte	1
	.8byte	1
	.8byte	1
	.8byte	.LcamlDomains__const_block204
	.data
	.align	8
	.8byte	2828
.LcamlDomains__const_block204:
	.8byte	21
	.8byte	1
	.data
	.align	8
	.8byte	5116
.LcamlDomains__immstring202:
	.ascii	"recommended_domain_count="
	.space	6
	.byte	6
	.data
	.align	8
	.8byte	2827
.LcamlDomains__const_block284:
	.8byte	.LcamlDomains__immstring282
	.8byte	.LcamlDomains__const_block249
	.data
	.align	8
	.8byte	4092
.LcamlDomains__immstring282:
	.ascii	"Safe.spawn domain "
	.space	5
	.byte	5
	.data
	.align	8
	.8byte	2827
.LcamlDomains__const_block251:
	.8byte	.LcamlDomains__immstring237
	.8byte	.LcamlDomains__const_block249
	.data
	.align	8
	.8byte	4868
.LcamlDomains__const_block249:
	.8byte	1
	.8byte	1
	.8byte	1
	.8byte	.LcamlDomains__const_block247
	.data
	.align	8
	.8byte	2827
.LcamlDomains__const_block247:
	.8byte	.LcamlDomains__immstring239
	.8byte	.LcamlDomains__const_block245
	.data
	.align	8
	.8byte	4868
.LcamlDomains__const_block245:
	.8byte	1
	.8byte	1
	.8byte	1
	.8byte	.LcamlDomains__const_block243
	.data
	.align	8
	.8byte	2827
.LcamlDomains__const_block243:
	.8byte	.LcamlDomains__immstring241
	.8byte	1
	.data
	.align	8
	.8byte	3068
.LcamlDomains__immstring241:
	.ascii	" primes\12"
	.space	7
	.byte	7
	.data
	.align	8
	.8byte	2044
.LcamlDomains__immstring239:
	.ascii	": "
	.space	5
	.byte	5
	.data
	.align	8
	.8byte	4092
.LcamlDomains__immstring237:
	.ascii	"spawn      domain "
	.space	5
	.byte	5
	.text
	.align	16
	.globl	camlDomains__loop_57_14_code
camlDomains__loop_57_14_code:
.LcamlDomains__loop_57_14_code:
	.cfi_startproc
	.cfi_def_cfa_offset 8
	subq	$8, %rsp
	.cfi_adjust_cfa_offset 8
	movq	%rbx, (%rsp)
.L106:
	movq	16(%rbx), %rbx
	movq	(%rbx), %rax
	testb	$1, %al
	je	.L117
	movq	8(%rbx), %rsi
	movq	16(%rbx), %rdi
	movq	caml_ml_condition_wait@GOTPCREL(%rip), %rax
	call	caml_c_call@PLT
.L123:
	cmpq	(%r14), %r15
	jbe	.L124
.L125:
	movq	(%rsp), %rbx
	jmp	.L106
	.align	4
.L117:
	movq	(%rax), %rax
	addq	$8, %rsp
	.cfi_adjust_cfa_offset -8
	ret
	.cfi_adjust_cfa_offset 8
.L124:
	call	.Lcaml_call_gc_
.L126:
	jmp	.L125
	.cfi_adjust_cfa_offset -8
	.cfi_endproc
	.type camlDomains__loop_57_14_code,@function
	.size camlDomains__loop_57_14_code,. - camlDomains__loop_57_14_code
	.text
	.align	16
	.globl	camlDomains__loop_57_19_code
camlDomains__loop_57_19_code:
.LcamlDomains__loop_57_19_code:
	.cfi_startproc
	.cfi_def_cfa_offset 8
	subq	$8, %rsp
	.cfi_adjust_cfa_offset 8
	movq	%rbx, (%rsp)
.L133:
	movq	16(%rbx), %rbx
	movq	(%rbx), %rax
	testb	$1, %al
	je	.L144
	movq	8(%rbx), %rsi
	movq	16(%rbx), %rdi
	movq	caml_ml_condition_wait@GOTPCREL(%rip), %rax
	call	caml_c_call@PLT
.L150:
	cmpq	(%r14), %r15
	jbe	.L151
.L152:
	movq	(%rsp), %rbx
	jmp	.L133
	.align	4
.L144:
	movq	(%rax), %rax
	addq	$8, %rsp
	.cfi_adjust_cfa_offset -8
	ret
	.cfi_adjust_cfa_offset 8
.L151:
	call	.Lcaml_call_gc_
.L153:
	jmp	.L152
	.cfi_adjust_cfa_offset -8
	.cfi_endproc
	.type camlDomains__loop_57_19_code,@function
	.size camlDomains__loop_57_19_code,. - camlDomains__loop_57_19_code
	.text
	.align	16
	.globl	camlDomains__sieve_0_7_code
camlDomains__sieve_0_7_code:
.LcamlDomains__sieve_0_7_code:
	.cfi_startproc
	.cfi_def_cfa_offset 8
	subq	$8, %rsp
	.cfi_adjust_cfa_offset 8
	movl	$125009, %edi
	movq	caml_create_bytes@GOTPCREL(%rip), %rax
	call	caml_c_call@PLT
.L271:
	movq	%rax, %rbx
	movl	$511, %ecx
	movl	$125009, %edx
	movl	$1, %esi
	movq	%rbx, %rdi
	movq	%rsp, %r13
	.cfi_remember_state
	.cfi_def_cfa_register %r13
	movq	104(%r14), %rsp
	call	caml_fill_bytes@PLT
	movq	%r13, %rsp
	.cfi_restore_state
	movl	$3, %eax
.L165:
	leaq	1(%rax,%rax), %rdi
	movq	%rdi, %rsi
	sarq	$1, %rsi
	leaq	-1(%rdi), %rdx
	imulq	%rsi, %rdx
	leaq	1(%rdx), %rsi
	cmpq	$2000001, %rsi
	jg	.L232
	movq	%rax, %rcx
	andl	$15, %ecx
	sarq	$1, %rcx
	movl	$2, %edx
	salq	%cl, %rdx
	leaq	1(%rdx), %rcx
	movq	%rax, %rdx
	shrq	$4, %rdx
	movzbq	(%rbx,%rdx), %rdx
	leaq	1(%rdx,%rdx), %rdx
	andq	%rcx, %rdx
	cmpq	$1, %rdx
	je	.L218
	sarq	$1, %rsi
	movq	%rsi, %rdx
	shrq	$63, %rdx
	addq	%rdx, %rsi
	sarq	$1, %rsi
	leaq	1(%rsi,%rsi), %rsi
	cmpq	$1000001, %rsi
	jge	.L218
.L197:
	movq	%rsi, %rdx
	shrq	$6, %rdx
	orq	$1, %rdx
	leaq	-7(,%rdx,8), %rdx
	sarq	$1, %rdx
	movq	%rsi, %rcx
	andl	$127, %ecx
	sarq	$1, %rcx
	movl	$1, %r8d
	salq	%cl, %r8
	xorq	$-1, %r8
	movq	(%rbx,%rdx), %rcx
	andq	%r8, %rcx
	movq	%rcx, (%rbx,%rdx)
	leaq	-1(%rsi,%rdi), %rsi
	cmpq	(%r14), %r15
	jbe	.L272
.L273:
	cmpq	$1000001, %rsi
	jl	.L197
.L218:
	addq	$2, %rax
	cmpq	(%r14), %r15
	jbe	.L275
.L276:
	jmp	.L165
	.align	4
.L232:
	movl	$3, %eax
	movl	$1, %edi
.L234:
	leaq	1(%rdi,%rdi), %rsi
	movq	%rsi, %rcx
	andl	$15, %ecx
	sarq	$1, %rcx
	movl	$2, %edx
	salq	%cl, %rdx
	incq	%rdx
	shrq	$4, %rsi
	movzbq	(%rbx,%rsi), %rsi
	leaq	1(%rsi,%rsi), %rsi
	andq	%rdx, %rsi
	cmpq	$1, %rsi
	je	.L254
	addq	$2, %rax
.L254:
	incq	%rdi
	cmpq	$499999, %rdi
	jg	.L259
	cmpq	(%r14), %r15
	jbe	.L278
.L279:
	jmp	.L234
	.align	4
.L259:
	addq	$8, %rsp
	.cfi_adjust_cfa_offset -8
	ret
	.cfi_adjust_cfa_offset 8
.L278:
	call	.Lcaml_call_gc_
.L280:
	jmp	.L279
.L275:
	call	.Lcaml_call_gc_
.L277:
	jmp	.L276
.L272:
	call	.Lcaml_call_gc_
.L274:
	jmp	.L273
	.cfi_adjust_cfa_offset -8
	.cfi_endproc
	.type camlDomains__sieve_0_7_code,@function
	.size camlDomains__sieve_0_7_code,. - camlDomains__sieve_0_7_code
	.text
	.align	16
	.globl	camlDomains__passes_2_9_code
camlDomains__passes_2_9_code:
.LcamlDomains__passes_2_9_code:
	.cfi_startproc
	.cfi_def_cfa_offset 8
	subq	$8, %rsp
	.cfi_adjust_cfa_offset 8
	pushq	%r10
	.cfi_adjust_cfa_offset 8
	leaq	-376(%rsp), %r10
	cmpq	40(%r14), %r10
	popq	%r10
	.cfi_adjust_cfa_offset -8
	jb	.L304
.L305:
	movl	$1, %ebx
.L290:
	movq	%rbx, (%rsp)
	movl	$1, %eax
	call	camlDomains__sieve_0_7_code@PLT
.L306:
	movq	(%rsp), %rbx
	incq	%rbx
	cmpq	$100, %rbx
	jg	.L296
	cmpq	(%r14), %r15
	jbe	.L307
.L308:
	jmp	.L290
	.align	4
.L296:
	addq	$8, %rsp
	.cfi_adjust_cfa_offset -8
	ret
	.cfi_adjust_cfa_offset 8
.L307:
	call	.Lcaml_call_gc_
.L309:
	jmp	.L308
.L304:
	push	$34
	.cfi_adjust_cfa_offset 8
	call	caml_call_realloc_stack@PLT
	addq	$8, %rsp
	.cfi_adjust_cfa_offset -8
	jmp	.L305
	.cfi_adjust_cfa_offset -8
	.cfi_endproc
	.type camlDomains__passes_2_9_code,@function
	.size camlDomains__passes_2_9_code,. - camlDomains__passes_2_9_code
	.text
	.align	16
	.globl	camlDomains__fn$5bdomains.ml$3a43$2c23$2d$2d129$5d_3_10_code
camlDomains__fn$5bdomains.ml$3a43$2c23$2d$2d129$5d_3_10_code:
.LcamlDomains__fn$5bdomains.ml$3a43$2c23$2d$2d129$5d_3_10_code:
	.cfi_startproc
	movq	camlDomains__passes_8@GOTPCREL(%rip), %rax
	jmp	camlStdlib__Domain__spawn_90_227_code@PLT
	.cfi_endproc
	.type camlDomains__fn$5bdomains.ml$3a43$2c23$2d$2d129$5d_3_10_code,@function
	.size camlDomains__fn$5bdomains.ml$3a43$2c23$2d$2d129$5d_3_10_code,. - camlDomains__fn$5bdomains.ml$3a43$2c23$2d$2d129$5d_3_10_code
	.text
	.align	16
	.globl	camlDomains__fn$5bdomains.ml$3a49$2c23$2d$2d97$5d_5_15_code
camlDomains__fn$5bdomains.ml$3a49$2c23$2d$2d97$5d_5_15_code:
.LcamlDomains__fn$5bdomains.ml$3a49$2c23$2d$2d97$5d_5_15_code:
	.cfi_startproc
	movq	camlDomains__passes_8@GOTPCREL(%rip), %rax
	jmp	camlStdlib__Domain__spawn_90_227_code@PLT
	.cfi_endproc
	.type camlDomains__fn$5bdomains.ml$3a49$2c23$2d$2d97$5d_5_15_code,@function
	.size camlDomains__fn$5bdomains.ml$3a49$2c23$2d$2d97$5d_5_15_code,. - camlDomains__fn$5bdomains.ml$3a49$2c23$2d$2d97$5d_5_15_code
	.text
	.align	16
	.globl	camlDomains__entry
camlDomains__entry:
.LcamlDomains__entry:
	.cfi_startproc
	.cfi_def_cfa_offset 8
	subq	$24, %rsp
	.cfi_adjust_cfa_offset 24
	movl	$1, %eax
	movq	%rax, %rdi
	movq	%rsp, %r13
	.cfi_remember_state
	.cfi_def_cfa_register %r13
	movq	104(%r14), %rsp
	call	caml_recommended_domain_count@PLT
	movq	%r13, %rsp
	.cfi_restore_state
	pushq	%r10
	.cfi_adjust_cfa_offset 8
	leaq	-392(%rsp), %r10
	cmpq	40(%r14), %r10
	popq	%r10
	.cfi_adjust_cfa_offset -8
	jb	.L415
.L416:
	movq	%rax, (%rsp)
	leaq	.LcamlDomains__const_block208(%rip), %rdi
	movl	$1, %ebx
	movq	camlStdlib__Printf__fn$5b$2fworkspace_root$2fprintf.ml$3a27$2c14$2d$2d48$5d_31@GOTPCREL(%rip), %rax
	call	camlCamlinternalFormat__make_printf_120_401_code@PLT
.L417:
	movq	%rax, %rbx
	movq	(%rbx), %rdi
	movq	(%rsp), %rax
	call	*%rdi
.L418:
	leaq	.LcamlDomains__fn$5bdomains.ml$3a43$2c23$2d$2d129$5d_9(%rip), %rdi
	movl	$7, %ebx
	movl	$1, %eax
	call	camlStdlib__List__init_11_109_code@PLT
.L419:
	movl	$1, %ebx
	testb	$1, %al
	jne	.L365
.L342:
	movq	%rbx, (%rsp)
	movq	64(%r14), %rbx
	movq	%rbx, 16(%rsp)
	movq	(%rax), %rbx
	movq	%rax, 8(%rsp)
	movq	8(%rbx), %rax
	movq	64(%r14), %rbx
	subq	$32, %rbx
	movq	%rbx, 64(%r14)
	cmpq	80(%r14), %rbx
	jl	.L420
.L421:
	addq	72(%r14), %rbx
	addq	$8, %rbx
	movq	$4087, -8(%rbx)
	leaq	.LcamlDomains__loop_57_14_code(%rip), %rdi
	movq	%rdi, (%rbx)
	movabsq	$108086391056891909, %rdi
	movq	%rdi, 8(%rbx)
	movq	%rax, 16(%rbx)
	movq	8(%rax), %rax
	call	camlStdlib__Mutex__protect_0_5_code@PLT
.L422:
	movzbq	-8(%rax), %rbx
	movq	(%rsp), %rdi
	movq	8(%rsp), %rsi
	movq	16(%rsp), %rdx
	testq	%rbx, %rbx
	je	.L354
	movq	(%rax), %rax
	movq	48(%r14), %rsp
	popq	48(%r14)
	popq	%r11
	jmp	*%r11
.L354:
	movq	%rsi, 8(%rsp)
	movq	%rdi, (%rsp)
	movq	(%rax), %rax
	movq	%rax, 16(%rsp)
	movq	%rdx, 64(%r14)
	leaq	.LcamlDomains__const_block251(%rip), %rdi
	movl	$1, %ebx
	movq	camlStdlib__Printf__fn$5b$2fworkspace_root$2fprintf.ml$3a27$2c14$2d$2d48$5d_31@GOTPCREL(%rip), %rax
	call	camlCamlinternalFormat__make_printf_120_401_code@PLT
.L423:
	movq	%rax, %rdi
	movq	(%rsp), %rbx
	movq	%rbx, %rax
	movq	%rbx, (%rsp)
	movq	16(%rsp), %rbx
	call	caml_apply2@PLT
.L424:
	movq	8(%rsp), %rax
	movq	8(%rax), %rax
	movq	(%rsp), %rbx
	addq	$2, %rbx
	testb	$1, %al
	je	.L342
.L365:
	leaq	.LcamlDomains__fn$5bdomains.ml$3a49$2c23$2d$2d97$5d_11(%rip), %rdi
	movl	$7, %ebx
	movl	$1, %eax
	call	camlStdlib__List__init_11_109_code@PLT
.L425:
	movl	$1, %ebx
	testb	$1, %al
	jne	.L399
.L375:
	movq	%rbx, (%rsp)
	movq	64(%r14), %rbx
	movq	%rbx, 16(%rsp)
	movq	(%rax), %rbx
	movq	%rax, 8(%rsp)
	movq	8(%rbx), %rax
	movq	64(%r14), %rbx
	subq	$32, %rbx
	movq	%rbx, 64(%r14)
	cmpq	80(%r14), %rbx
	jl	.L426
.L427:
	addq	72(%r14), %rbx
	addq	$8, %rbx
	movq	$4087, -8(%rbx)
	leaq	.LcamlDomains__loop_57_19_code(%rip), %rdi
	movq	%rdi, (%rbx)
	movabsq	$108086391056891909, %rdi
	movq	%rdi, 8(%rbx)
	movq	%rax, 16(%rbx)
	movq	8(%rax), %rax
	call	camlStdlib__Mutex__protect_0_5_code@PLT
.L428:
	movzbq	-8(%rax), %rbx
	movq	(%rsp), %rdi
	movq	8(%rsp), %rsi
	movq	16(%rsp), %rdx
	testq	%rbx, %rbx
	je	.L387
	movq	(%rax), %rax
	movq	48(%r14), %rsp
	popq	48(%r14)
	popq	%r11
	jmp	*%r11
.L387:
	movq	%rsi, 8(%rsp)
	movq	%rdi, (%rsp)
	movq	(%rax), %rax
	movq	%rax, 16(%rsp)
	movq	%rdx, 64(%r14)
	leaq	.LcamlDomains__const_block284(%rip), %rdi
	movl	$1, %ebx
	movq	camlStdlib__Printf__fn$5b$2fworkspace_root$2fprintf.ml$3a27$2c14$2d$2d48$5d_31@GOTPCREL(%rip), %rax
	call	camlCamlinternalFormat__make_printf_120_401_code@PLT
.L429:
	movq	%rax, %rdi
	movq	(%rsp), %rbx
	movq	%rbx, %rax
	movq	%rbx, (%rsp)
	movq	16(%rsp), %rbx
	call	caml_apply2@PLT
.L430:
	movq	8(%rsp), %rax
	movq	8(%rax), %rax
	movq	(%rsp), %rbx
	addq	$2, %rbx
	testb	$1, %al
	je	.L375
.L399:
	movl	$1, %eax
	addq	$24, %rsp
	.cfi_adjust_cfa_offset -24
	ret
	.cfi_adjust_cfa_offset 24
.L426:
	call	caml_call_local_realloc@PLT
	jmp	.L427
.L420:
	call	caml_call_local_realloc@PLT
	jmp	.L421
.L415:
	push	$36
	.cfi_adjust_cfa_offset 8
	call	caml_call_realloc_stack@PLT
	addq	$8, %rsp
	.cfi_adjust_cfa_offset -8
	jmp	.L416
	.cfi_adjust_cfa_offset -24
	.cfi_endproc
	.type camlDomains__entry,@function
	.size camlDomains__entry,. - camlDomains__entry
	.data
	.align	8
	.text
	.align	4
	.text
	.globl	camlDomains__code_end
camlDomains__code_end:
	.data
	.align	8
	.data
	.8byte	0
	.globl	camlDomains__data_end
camlDomains__data_end:
	.8byte	0
	.text
	.align	8
	.globl	camlDomains__frametable
camlDomains__frametable:
	.8byte	20
	.4byte	(.L430 - .) + 0
	.2byte	33
	.2byte	1
	.2byte	8
	.align	4
	.4byte	(.L431 - .) + 0
	.align	8
	.4byte	(.L429 - .) + 0
	.2byte	33
	.2byte	2
	.2byte	8
	.2byte	16
	.align	4
	.4byte	(.L432 - .) + 0
	.align	8
	.4byte	(.L428 - .) + 0
	.2byte	33
	.2byte	1
	.2byte	8
	.align	4
	.4byte	(.L433 - .) + 0
	.align	8
	.4byte	(.L425 - .) + 0
	.2byte	33
	.2byte	0
	.align	4
	.4byte	(.L434 - .) + 0
	.align	8
	.4byte	(.L424 - .) + 0
	.2byte	33
	.2byte	1
	.2byte	8
	.align	4
	.4byte	(.L435 - .) + 0
	.align	8
	.4byte	(.L423 - .) + 0
	.2byte	33
	.2byte	2
	.2byte	8
	.2byte	16
	.align	4
	.4byte	(.L436 - .) + 0
	.align	8
	.4byte	(.L422 - .) + 0
	.2byte	33
	.2byte	1
	.2byte	8
	.align	4
	.4byte	(.L437 - .) + 0
	.align	8
	.4byte	(.L419 - .) + 0
	.2byte	33
	.2byte	0
	.align	4
	.4byte	(.L438 - .) + 0
	.align	8
	.4byte	(.L418 - .) + 0
	.2byte	33
	.2byte	0
	.align	4
	.4byte	(.L439 - .) + 0
	.align	8
	.4byte	(.L417 - .) + 0
	.2byte	33
	.2byte	1
	.2byte	0
	.align	4
	.4byte	(.L440 - .) + 0
	.align	8
	.4byte	(.L309 - .) + 0
	.2byte	18
	.2byte	0
	.byte	0
	.align	8
	.4byte	(.L306 - .) + 0
	.2byte	17
	.2byte	0
	.align	4
	.4byte	(.L441 - .) + 0
	.align	8
	.4byte	(.L280 - .) + 0
	.2byte	18
	.2byte	1
	.2byte	3
	.byte	0
	.align	8
	.4byte	(.L277 - .) + 0
	.2byte	18
	.2byte	1
	.2byte	3
	.byte	0
	.align	8
	.4byte	(.L274 - .) + 0
	.2byte	18
	.2byte	1
	.2byte	3
	.byte	0
	.align	8
	.4byte	(.L271 - .) + 0
	.2byte	17
	.2byte	0
	.align	4
	.4byte	(.L442 - .) + 0
	.align	8
	.4byte	(.L153 - .) + 0
	.2byte	18
	.2byte	1
	.2byte	0
	.byte	0
	.align	8
	.4byte	(.L150 - .) + 0
	.2byte	17
	.2byte	1
	.2byte	0
	.align	4
	.4byte	(.L443 - .) + 0
	.align	8
	.4byte	(.L126 - .) + 0
	.2byte	18
	.2byte	1
	.2byte	0
	.byte	0
	.align	8
	.4byte	(.L123 - .) + 0
	.2byte	17
	.2byte	1
	.2byte	0
	.align	4
	.4byte	(.L443 - .) + 0
	.align	8
	.align	4
.L436:
	.4byte	(.L445 - .) + 1
	.4byte	14158328
	.4byte	(.L446 - .) + 1
	.4byte	17847640
	.4byte	(.L447 - .) + 1
	.4byte	19940632
	.4byte	(.L449 - .) + 1
	.4byte	24143584
	.4byte	(.L451 - .) + 1
	.4byte	63451272
	.4byte	(.L451 - .) + 1
	.4byte	64504024
	.4byte	(.L452 - .) + 0
	.4byte	24120064
	.align	4
.L432:
	.4byte	(.L445 - .) + 1
	.4byte	14158328
	.4byte	(.L446 - .) + 1
	.4byte	17847640
	.4byte	(.L447 - .) + 1
	.4byte	19940632
	.4byte	(.L449 - .) + 1
	.4byte	26765024
	.4byte	(.L451 - .) + 1
	.4byte	63451272
	.4byte	(.L451 - .) + 1
	.4byte	64504024
	.4byte	(.L452 - .) + 0
	.4byte	26741504
	.align	4
.L439:
	.4byte	(.L452 - .) + 0
	.4byte	21498528
	.align	4
.L434:
	.4byte	(.L453 - .) + 1
	.4byte	40372384
	.4byte	(.L452 - .) + -2080374784
	.4byte	25767424
	.align	4
.L435:
	.4byte	(.L449 - .) + 1
	.4byte	24143584
	.4byte	(.L451 - .) + 1
	.4byte	63451272
	.4byte	(.L451 - .) + 1
	.4byte	64504024
	.4byte	(.L452 - .) + 0
	.4byte	24120064
	.align	4
.L441:
	.4byte	(.L454 - .) + 0
	.4byte	19426584
	.align	4
.L442:
	.4byte	(.L456 - .) + 1
	.4byte	31467664
	.4byte	(.L457 - .) + 0
	.4byte	6304184
	.align	4
.L437:
	.4byte	(.L459 - .) + 1
	.4byte	237513040
	.4byte	(.L460 - .) + 1
	.4byte	-2147295232
	.4byte	(.L451 - .) + 1
	.4byte	63451272
	.4byte	(.L451 - .) + 1
	.4byte	64504024
	.4byte	(.L452 - .) + 0
	.4byte	24120064
	.align	4
.L433:
	.4byte	(.L459 - .) + 1
	.4byte	237513040
	.4byte	(.L460 - .) + 1
	.4byte	-2147274752
	.4byte	(.L451 - .) + 1
	.4byte	63451272
	.4byte	(.L451 - .) + 1
	.4byte	64504024
	.4byte	(.L452 - .) + 0
	.4byte	26741504
	.align	4
.L431:
	.4byte	(.L449 - .) + 1
	.4byte	26765024
	.4byte	(.L451 - .) + 1
	.4byte	63451272
	.4byte	(.L451 - .) + 1
	.4byte	64504024
	.4byte	(.L452 - .) + 0
	.4byte	26741504
	.align	4
.L443:
	.4byte	(.L462 - .) + 1006632961
	.4byte	10551912
	.4byte	(.L463 - .) + 0
	.4byte	234891688
	.align	4
.L440:
	.4byte	(.L445 - .) + 1
	.4byte	14158328
	.4byte	(.L446 - .) + 1
	.4byte	17847640
	.4byte	(.L447 - .) + 1
	.4byte	19940632
	.4byte	(.L452 - .) + 0
	.4byte	21498528
	.align	4
.L438:
	.4byte	(.L453 - .) + 1
	.4byte	40372384
	.4byte	(.L452 - .) + -805306368
	.4byte	22686825
.L458:
	.ascii	"domain.ml\0"
.L450:
	.ascii	"list.ml\0"
.L455:
	.ascii	"bytes.ml\0"
.L444:
	.ascii	"printf.ml\0"
.L461:
	.ascii	"stdlib/condition.ml\0"
.L448:
	.ascii	"domains.ml\0"
	.align	4
.L462:
	.4byte	(.L461 - .) + 0
	.ascii	"Stdlib__Condition.(partial)\0"
	.align	4
.L449:
	.4byte	(.L448 - .) + 0
	.ascii	"Domains.(fun)\0"
	.align	4
.L460:
	.4byte	(.L448 - .) + 0
	.2byte	77
	.2byte	92
	.4byte	92
	.ascii	"Domains.(fun)\0"
	.align	4
.L456:
	.4byte	(.L455 - .) + 0
	.ascii	"Stdlib__Bytes.make\0"
	.align	4
.L452:
	.4byte	(.L448 - .) + 0
	.ascii	"Domains\0"
	.align	4
.L457:
	.4byte	(.L448 - .) + 0
	.ascii	"Domains.sieve\0"
	.align	4
.L453:
	.4byte	(.L450 - .) + 0
	.ascii	"Stdlib__List.init\0"
	.align	4
.L451:
	.4byte	(.L450 - .) + 0
	.ascii	"Stdlib__List.iteri\0"
	.align	4
.L447:
	.4byte	(.L444 - .) + 0
	.ascii	"Stdlib__Printf.printf\0"
	.align	4
.L446:
	.4byte	(.L444 - .) + 0
	.ascii	"Stdlib__Printf.fprintf\0"
	.align	4
.L454:
	.4byte	(.L448 - .) + 0
	.ascii	"Domains.passes\0"
	.align	4
.L445:
	.4byte	(.L444 - .) + 0
	.ascii	"Stdlib__Printf.kfprintf\0"
	.align	4
.L463:
	.4byte	(.L458 - .) + 0
	.ascii	"Stdlib__Domain.Runtime_5.join.loop\0"
	.align	4
.L459:
	.4byte	(.L458 - .) + 0
	.ascii	"Stdlib__Domain.Runtime_5.join\0"
	.align	8
	.size camlDomains__frametable,. - camlDomains__frametable
	.data
	.section .note.GNU-stack,"",@progbits
