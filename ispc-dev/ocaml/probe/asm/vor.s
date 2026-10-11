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
	.globl	camlVor__data_begin
camlVor__data_begin:
	.text
	.globl	camlVor__code_begin
camlVor__code_begin:
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
	.globl	camlVor__gc_roots
camlVor__gc_roots:
.LcamlVor__gc_roots:
	.8byte	0
	.data
	.align	8
	.8byte	6912
	.globl	camlVor
camlVor:
.LcamlVor:
	.8byte	131073
	.8byte	40001
	.8byte	camlVor__or_loop128_7
	.8byte	camlVor__or_loop256_8
	.8byte	camlVor__or_loop64_9
	.8byte	camlVor__check_10
	.data
	.align	8
	.8byte	4087
	.globl	camlVor__check_10
camlVor__check_10:
.LcamlVor__check_10:
	.8byte	caml_curry2
	.8byte	0x280000000000007
	.8byte	camlVor__check_3_10_code
	.data
	.align	8
	.8byte	4087
	.globl	camlVor__or_loop64_9
camlVor__or_loop64_9:
.LcamlVor__or_loop64_9:
	.8byte	caml_curry2
	.8byte	0x280000000000007
	.8byte	camlVor__or_loop64_2_9_code
	.data
	.align	8
	.8byte	4087
	.globl	camlVor__or_loop256_8
camlVor__or_loop256_8:
.LcamlVor__or_loop256_8:
	.8byte	caml_curry2
	.8byte	0x280000000000007
	.8byte	camlVor__or_loop256_1_8_code
	.data
	.align	8
	.8byte	4087
	.globl	camlVor__or_loop128_7
camlVor__or_loop128_7:
.LcamlVor__or_loop128_7:
	.8byte	caml_curry2
	.8byte	0x280000000000007
	.8byte	camlVor__or_loop128_0_7_code
	.data
	.align	8
	.8byte	2044
.LcamlVor__immstring254:
	.ascii	"or64"
	.space	3
	.byte	3
	.data
	.align	8
	.8byte	2044
.LcamlVor__immstring257:
	.ascii	"or128"
	.space	2
	.byte	2
	.data
	.align	8
	.8byte	2044
.LcamlVor__immstring259:
	.ascii	"or256"
	.space	2
	.byte	2
	.data
	.align	8
	.8byte	2818
	.globl	camlVor__const_block244
camlVor__const_block244:
.LcamlVor__const_block244:
	.8byte	camlVor__const_block224
	.8byte	camlVor__const_block242
	.data
	.align	8
	.8byte	2828
	.globl	camlVor__const_block242
camlVor__const_block242:
.LcamlVor__const_block242:
	.8byte	65
	.8byte	camlVor__const_block240
	.data
	.align	8
	.8byte	2818
	.globl	camlVor__const_block240
camlVor__const_block240:
.LcamlVor__const_block240:
	.8byte	1
	.8byte	camlVor__const_block238
	.data
	.align	8
	.8byte	2827
	.globl	camlVor__const_block238
camlVor__const_block238:
.LcamlVor__const_block238:
	.8byte	camlVor__immstring226
	.8byte	camlVor__const_block236
	.data
	.align	8
	.8byte	4872
	.globl	camlVor__const_block236
camlVor__const_block236:
.LcamlVor__const_block236:
	.8byte	camlVor__const_block228
	.8byte	1
	.8byte	camlVor__const_block230
	.8byte	camlVor__const_block234
	.data
	.align	8
	.8byte	2827
	.globl	camlVor__const_block234
camlVor__const_block234:
.LcamlVor__const_block234:
	.8byte	camlVor__immstring232
	.8byte	1
	.data
	.align	8
	.8byte	6140
	.globl	camlVor__immstring232
camlVor__immstring232:
.LcamlVor__immstring232:
	.ascii	" GB/s (dst read+write, src read)\12"
	.space	6
	.byte	6
	.data
	.align	8
	.8byte	1792
	.globl	camlVor__const_block230
camlVor__const_block230:
.LcamlVor__const_block230:
	.8byte	5
	.data
	.align	8
	.8byte	2816
	.globl	camlVor__const_block228
camlVor__const_block228:
.LcamlVor__const_block228:
	.8byte	1
	.8byte	1
	.data
	.align	8
	.8byte	2044
	.globl	camlVor__immstring226
camlVor__immstring226:
.LcamlVor__immstring226:
	.ascii	"  "
	.space	5
	.byte	5
	.data
	.align	8
	.8byte	2816
	.globl	camlVor__const_block224
camlVor__const_block224:
.LcamlVor__const_block224:
	.8byte	1
	.8byte	13
	.data
	.align	8
	.8byte	2044
	.globl	camlVor__immstring220
camlVor__immstring220:
.LcamlVor__immstring220:
	.ascii	"ok"
	.space	5
	.byte	5
	.data
	.align	8
	.8byte	2044
	.globl	camlVor__immstring218
camlVor__immstring218:
.LcamlVor__immstring218:
	.ascii	"WRONG"
	.space	2
	.byte	2
	.data
	.align	8
	.8byte	2816
	.globl	camlVor__block155
camlVor__block155:
.LcamlVor__block155:
	.8byte	caml_exn_Invalid_argument
	.8byte	camlVor__string153
	.data
	.align	8
	.8byte	4092
	.globl	camlVor__string153
camlVor__string153:
.LcamlVor__string153:
	.ascii	"index out of bounds"
	.space	4
	.byte	4
	.text
	.align	16
	.globl	camlVor__or_loop128_0_7_code
camlVor__or_loop128_0_7_code:
.LcamlVor__or_loop128_0_7_code:
	.cfi_startproc
	.cfi_def_cfa_offset 8
	subq	$8, %rsp
	.cfi_adjust_cfa_offset 8
	movl	$1, %edi
.L108:
	movq	%rdi, %rsi
	sarq	$1, %rsi
	vmovupd	(%rbx,%rsi), %xmm0
	vmovupd	(%rax,%rsi), %xmm1
	vorps	%xmm0, %xmm1, %xmm0
	vmovupd	%xmm0, (%rax,%rsi)
	addq	$32, %rdi
	cmpq	(%r14), %r15
	jbe	.L120
.L121:
	cmpq	$131073, %rdi
	jl	.L108
	movl	$1, %eax
	addq	$8, %rsp
	.cfi_adjust_cfa_offset -8
	ret
	.cfi_adjust_cfa_offset 8
.L120:
	call	.Lcaml_call_gc_
.L122:
	jmp	.L121
	.cfi_adjust_cfa_offset -8
	.cfi_endproc
	.type camlVor__or_loop128_0_7_code,@function
	.size camlVor__or_loop128_0_7_code,. - camlVor__or_loop128_0_7_code
	.text
	.align	16
	.globl	camlVor__or_loop256_1_8_code
camlVor__or_loop256_1_8_code:
.LcamlVor__or_loop256_1_8_code:
	.cfi_startproc
	.cfi_def_cfa_offset 8
	subq	$8, %rsp
	.cfi_adjust_cfa_offset 8
	movl	$1, %edi
.L131:
	movq	%rdi, %rsi
	sarq	$1, %rsi
	vmovupd	(%rbx,%rsi), %ymm0
	vmovupd	(%rax,%rsi), %ymm1
	vorps	%ymm0, %ymm1, %ymm0
	vmovupd	%ymm0, (%rax,%rsi)
	addq	$64, %rdi
	cmpq	(%r14), %r15
	jbe	.L143
.L144:
	cmpq	$131073, %rdi
	jl	.L131
	movl	$1, %eax
	addq	$8, %rsp
	.cfi_adjust_cfa_offset -8
	ret
	.cfi_adjust_cfa_offset 8
.L143:
	call	.Lcaml_call_gc_
.L145:
	jmp	.L144
	.cfi_adjust_cfa_offset -8
	.cfi_endproc
	.type camlVor__or_loop256_1_8_code,@function
	.size camlVor__or_loop256_1_8_code,. - camlVor__or_loop256_1_8_code
	.text
	.align	16
	.globl	camlVor__or_loop64_2_9_code
camlVor__or_loop64_2_9_code:
.LcamlVor__or_loop64_2_9_code:
	.cfi_startproc
	.cfi_def_cfa_offset 8
	subq	$8, %rsp
	.cfi_adjust_cfa_offset 8
	movl	$1, %edi
.L154:
	movq	%rdi, %rsi
	sarq	$1, %rsi
	movq	(%rbx,%rsi), %rcx
	movq	(%rax,%rsi), %rdx
	orq	%rcx, %rdx
	movq	%rdx, (%rax,%rsi)
	addq	$16, %rdi
	cmpq	(%r14), %r15
	jbe	.L166
.L167:
	cmpq	$131073, %rdi
	jl	.L154
	movl	$1, %eax
	addq	$8, %rsp
	.cfi_adjust_cfa_offset -8
	ret
	.cfi_adjust_cfa_offset 8
.L166:
	call	.Lcaml_call_gc_
.L168:
	jmp	.L167
	.cfi_adjust_cfa_offset -8
	.cfi_endproc
	.type camlVor__or_loop64_2_9_code,@function
	.size camlVor__or_loop64_2_9_code,. - camlVor__or_loop64_2_9_code
	.text
	.align	16
	.globl	camlVor__check_3_10_code
camlVor__check_3_10_code:
.LcamlVor__check_3_10_code:
	.cfi_startproc
	.cfi_def_cfa_offset 8
	subq	$72, %rsp
	.cfi_adjust_cfa_offset 72
	movq	%rax, (%rsp)
	movq	%rbx, %rdi
	movq	%rdi, 8(%rsp)
	movl	$131073, %edi
	movq	caml_create_bytes@GOTPCREL(%rip), %rax
	call	caml_c_call@PLT
.L361:
	pushq	%r10
	.cfi_adjust_cfa_offset 8
	leaq	-440(%rsp), %r10
	cmpq	40(%r14), %r10
	popq	%r10
	.cfi_adjust_cfa_offset -8
	jb	.L362
.L363:
	movq	%rax, %r12
	xorl	%eax, %eax
.L179:
	leaq	1(%rax,%rax), %rbx
	movq	%rbx, %rdi
	andl	$171, %edi
	cmpq	$1, %rdi
	jge	.L185
	movq	camlStdlib__Char__Pmakeblock168@GOTPCREL(%rip), %rax
	movq	48(%r14), %rsp
	popq	48(%r14)
	popq	%r11
	jmp	*%r11
	.align	4
.L185:
	cmpq	$511, %rdi
	jle	.L189
	movq	camlStdlib__Char__Pmakeblock168@GOTPCREL(%rip), %rax
	movq	48(%r14), %rsp
	popq	48(%r14)
	popq	%r11
	jmp	*%r11
	.align	4
.L189:
	sarq	$1, %rbx
	sarq	$1, %rdi
	movb	%dil, (%r12,%rbx)
	incq	%rax
	cmpq	$65535, %rax
	jg	.L197
	cmpq	(%r14), %r15
	jbe	.L364
.L365:
	jmp	.L179
	.align	4
.L197:
	movq	%r12, 16(%rsp)
	movl	$131073, %edi
	movq	caml_create_bytes@GOTPCREL(%rip), %rax
	call	caml_c_call@PLT
.L367:
	movq	%rax, %rbx
	xorl	%eax, %eax
.L212:
	leaq	1(%rax,%rax), %rdi
	movq	%rdi, %rsi
	imulq	$7, %rsi
	addq	$-6, %rsi
	andl	$341, %esi
	cmpq	$1, %rsi
	jge	.L220
	movq	camlStdlib__Char__Pmakeblock168@GOTPCREL(%rip), %rax
	movq	48(%r14), %rsp
	popq	48(%r14)
	popq	%r11
	jmp	*%r11
	.align	4
.L220:
	cmpq	$511, %rsi
	jle	.L224
	movq	camlStdlib__Char__Pmakeblock168@GOTPCREL(%rip), %rax
	movq	48(%r14), %rsp
	popq	48(%r14)
	popq	%r11
	jmp	*%r11
	.align	4
.L224:
	sarq	$1, %rdi
	sarq	$1, %rsi
	movb	%sil, (%rbx,%rdi)
	incq	%rax
	cmpq	$65535, %rax
	jg	.L232
	cmpq	(%r14), %r15
	jbe	.L368
.L369:
	jmp	.L212
	.align	4
.L232:
	movq	%rbx, 24(%rsp)
	movl	$131073, %edi
	movq	caml_create_bytes@GOTPCREL(%rip), %rax
	call	caml_c_call@PLT
.L371:
	movq	%rax, %rbx
	xorl	%edi, %edi
	movq	16(%rsp), %rax
	movq	24(%rsp), %rsi
.L250:
	movq	%rdi, %rsi
	salq	$1, %rsi
	sarq	$1, %rsi
	movq	24(%rsp), %rdx
	movq	-8(%rdx), %rdx
	salq	$8, %rdx
	shrq	$18, %rdx
	leaq	-1(,%rdx,8), %rdx
	movq	24(%rsp), %rcx
	movzbq	(%rcx,%rdx), %rcx
	subq	%rcx, %rdx
	cmpq	%rdx, %rsi
	jae	.L305
	movq	24(%rsp), %rdx
	movzbq	(%rdx,%rsi), %rdx
	leaq	1(%rdx,%rdx), %rdx
	movq	-8(%rax), %rcx
	salq	$8, %rcx
	shrq	$18, %rcx
	leaq	-1(,%rcx,8), %rcx
	movzbq	(%rax,%rcx), %r8
	subq	%r8, %rcx
	cmpq	%rcx, %rsi
	jae	.L299
	movzbq	(%rax,%rsi), %rcx
	leaq	1(%rcx,%rcx), %rcx
	orq	%rdx, %rcx
	cmpq	$1, %rcx
	jge	.L280
	movq	camlStdlib__Char__Pmakeblock168@GOTPCREL(%rip), %rax
	movq	48(%r14), %rsp
	popq	48(%r14)
	popq	%r11
	jmp	*%r11
	.align	4
.L280:
	cmpq	$511, %rcx
	jle	.L284
	movq	camlStdlib__Char__Pmakeblock168@GOTPCREL(%rip), %rax
	movq	48(%r14), %rsp
	popq	48(%r14)
	popq	%r11
	jmp	*%r11
	.align	4
.L284:
	sarq	$1, %rcx
	movb	%cl, (%rbx,%rsi)
	incq	%rdi
	cmpq	$65535, %rdi
	jg	.L291
	cmpq	(%r14), %r15
	jbe	.L372
.L373:
	jmp	.L250
	.align	4
.L291:
	movq	%rbx, 32(%rsp)
	movq	24(%rsp), %rbx
	movq	8(%rsp), %rdi
	call	caml_apply2@PLT
.L375:
	jmp	.L311
	.align	4
.L299:
	movq	camlVor__block155@GOTPCREL(%rip), %rax
	movq	48(%r14), %rsp
	popq	48(%r14)
	popq	%r11
	jmp	*%r11
	.align	4
.L305:
	movq	camlVor__block155@GOTPCREL(%rip), %rax
	movq	48(%r14), %rsp
	popq	48(%r14)
	popq	%r11
	jmp	*%r11
	.align	4
.L311:
	movq	16(%rsp), %r12
	movq	%r12, %rdi
	movq	32(%rsp), %rsi
	movq	%rsp, %r13
	.cfi_remember_state
	.cfi_def_cfa_register %r13
	movq	104(%r14), %rsp
	call	caml_bytes_equal@PLT
	movq	%r13, %rsp
	.cfi_restore_state
	movq	%rax, 40(%rsp)
	movl	$1, %edi
	movq	%rsp, %r13
	.cfi_remember_state
	.cfi_def_cfa_register %r13
	movq	104(%r14), %rsp
	call	caml_sys_time_unboxed@PLT
	movq	%r13, %rsp
	.cfi_restore_state
	vmovsd	%xmm0, 48(%rsp)
	movl	$1, %eax
	movq	8(%rsp), %rdi
	movq	24(%rsp), %rbx
.L320:
	movq	%rax, 32(%rsp)
	movq	%r12, %rax
	call	caml_apply2@PLT
.L376:
	movq	32(%rsp), %rax
	incq	%rax
	movq	8(%rsp), %rdi
	movq	16(%rsp), %r12
	movq	24(%rsp), %rbx
	cmpq	$20000, %rax
	jg	.L330
	cmpq	(%r14), %r15
	jbe	.L377
.L378:
	jmp	.L320
	.align	4
.L330:
	movl	$1, %edi
	movq	%rsp, %r13
	.cfi_remember_state
	.cfi_def_cfa_register %r13
	movq	104(%r14), %rsp
	call	caml_sys_time_unboxed@PLT
	movq	%r13, %rsp
	.cfi_restore_state
	movq	40(%rsp), %rax
	sarq	$1, %rax
	testq	%rax, %rax
	je	.L339
	movq	camlVor__immstring220@GOTPCREL(%rip), %rax
	jmp	.L342
	.align	4
.L339:
	movq	camlVor__immstring218@GOTPCREL(%rip), %rax
.L342:
	movq	%rax, 8(%rsp)
	vmovsd	%xmm0, 56(%rsp)
	movq	camlVor__const_block244@GOTPCREL(%rip), %rdi
	movl	$1, %ebx
	movq	camlStdlib__Printf__fn$5b$2fworkspace_root$2fprintf.ml$3a27$2c14$2d$2d48$5d_31@GOTPCREL(%rip), %rax
	call	camlCamlinternalFormat__make_printf_120_401_code@PLT
.L380:
	movq	%rax, %rsi
	subq	$16, %r15
	cmpq	(%r14), %r15
	jb	.L381
.L383:
	leaq	8(%r15), %rdi
	movq	$1277, -8(%rdi)
	vmovsd	.L384(%rip), %xmm0
	vmovsd	48(%rsp), %xmm1
	vmovsd	56(%rsp), %xmm2
	vsubsd	%xmm1, %xmm2, %xmm1
	vmovsd	.L385(%rip), %xmm2
	vdivsd	%xmm1, %xmm2, %xmm1
	vdivsd	%xmm0, %xmm1, %xmm0
	vmovsd	%xmm0, (%rdi)
	movq	(%rsp), %rax
	movq	8(%rsp), %rbx
	addq	$72, %rsp
	.cfi_adjust_cfa_offset -72
	jmp	caml_apply3@PLT
	.cfi_adjust_cfa_offset 72
.L381:
	call	.Lcaml_call_gc_
.L382:
	jmp	.L383
.L377:
	call	.Lcaml_call_gc_
.L379:
	jmp	.L378
.L372:
	call	.Lcaml_call_gc_
.L374:
	jmp	.L373
.L368:
	call	.Lcaml_call_gc_
.L370:
	jmp	.L369
.L364:
	call	.Lcaml_call_gc_
.L366:
	jmp	.L365
.L362:
	push	$42
	.cfi_adjust_cfa_offset 8
	call	caml_call_realloc_stack@PLT
	addq	$8, %rsp
	.cfi_adjust_cfa_offset -8
	jmp	.L363
	.cfi_adjust_cfa_offset -72
	.cfi_endproc
	.type camlVor__check_3_10_code,@function
	.size camlVor__check_3_10_code,. - camlVor__check_3_10_code
	.text
	.align	16
	.globl	camlVor__entry
camlVor__entry:
.LcamlVor__entry:
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
	jb	.L401
.L402:
	movq	camlVor__or_loop64_9@GOTPCREL(%rip), %rbx
	leaq	.LcamlVor__immstring254(%rip), %rax
	call	camlVor__check_3_10_code@PLT
.L403:
	movq	camlVor__or_loop128_7@GOTPCREL(%rip), %rbx
	leaq	.LcamlVor__immstring257(%rip), %rax
	call	camlVor__check_3_10_code@PLT
.L404:
	movq	camlVor__or_loop256_8@GOTPCREL(%rip), %rbx
	leaq	.LcamlVor__immstring259(%rip), %rax
	call	camlVor__check_3_10_code@PLT
.L405:
	movl	$1, %eax
	addq	$8, %rsp
	.cfi_adjust_cfa_offset -8
	ret
	.cfi_adjust_cfa_offset 8
.L401:
	push	$34
	.cfi_adjust_cfa_offset 8
	call	caml_call_realloc_stack@PLT
	addq	$8, %rsp
	.cfi_adjust_cfa_offset -8
	jmp	.L402
	.cfi_adjust_cfa_offset -8
	.cfi_endproc
	.type camlVor__entry,@function
	.size camlVor__entry,. - camlVor__entry
	.data
	.align	8
	.8byte	caml_avx_vec256_or
	.8byte	caml_sse_vec128_or
	.section .rodata.cst8,"aM",@progbits,8
	.align	8
.L385:
	.8byte	0x41d3880000000000
.L384:
	.8byte	0x41cdcd6500000000
	.text
	.align	4
	.text
	.globl	camlVor__code_end
camlVor__code_end:
	.data
	.align	8
	.data
	.8byte	0
	.globl	camlVor__data_end
camlVor__data_end:
	.8byte	0
	.text
	.align	8
	.globl	camlVor__frametable
camlVor__frametable:
	.8byte	17
	.4byte	(.L405 - .) + 0
	.2byte	17
	.2byte	0
	.align	4
	.4byte	(.L406 - .) + 0
	.align	8
	.4byte	(.L404 - .) + 0
	.2byte	17
	.2byte	0
	.align	4
	.4byte	(.L407 - .) + 0
	.align	8
	.4byte	(.L403 - .) + 0
	.2byte	17
	.2byte	0
	.align	4
	.4byte	(.L408 - .) + 0
	.align	8
	.4byte	(.L382 - .) + 0
	.2byte	82
	.2byte	3
	.2byte	0
	.2byte	7
	.2byte	8
	.byte	1
	.byte	0
	.align	8
	.4byte	(.L380 - .) + 0
	.2byte	81
	.2byte	2
	.2byte	0
	.2byte	8
	.align	4
	.4byte	(.L409 - .) + 0
	.align	8
	.4byte	(.L379 - .) + 0
	.2byte	82
	.2byte	8
	.2byte	0
	.2byte	3
	.2byte	5
	.2byte	8
	.2byte	16
	.2byte	17
	.2byte	24
	.2byte	40
	.byte	0
	.align	8
	.4byte	(.L376 - .) + 0
	.2byte	81
	.2byte	5
	.2byte	0
	.2byte	8
	.2byte	16
	.2byte	24
	.2byte	40
	.align	4
	.4byte	(.L410 - .) + 0
	.align	8
	.4byte	(.L375 - .) + 0
	.2byte	81
	.2byte	5
	.2byte	0
	.2byte	8
	.2byte	16
	.2byte	24
	.2byte	32
	.align	4
	.4byte	(.L411 - .) + 0
	.align	8
	.4byte	(.L374 - .) + 0
	.2byte	82
	.2byte	6
	.2byte	0
	.2byte	1
	.2byte	3
	.2byte	8
	.2byte	16
	.2byte	24
	.byte	0
	.align	8
	.4byte	(.L371 - .) + 0
	.2byte	81
	.2byte	4
	.2byte	0
	.2byte	8
	.2byte	16
	.2byte	24
	.align	4
	.4byte	(.L412 - .) + 0
	.align	8
	.4byte	(.L370 - .) + 0
	.2byte	82
	.2byte	4
	.2byte	0
	.2byte	3
	.2byte	8
	.2byte	16
	.byte	0
	.align	8
	.4byte	(.L367 - .) + 0
	.2byte	81
	.2byte	3
	.2byte	0
	.2byte	8
	.2byte	16
	.align	4
	.4byte	(.L413 - .) + 0
	.align	8
	.4byte	(.L366 - .) + 0
	.2byte	82
	.2byte	3
	.2byte	0
	.2byte	8
	.2byte	17
	.byte	0
	.align	8
	.4byte	(.L361 - .) + 0
	.2byte	81
	.2byte	2
	.2byte	0
	.2byte	8
	.align	4
	.4byte	(.L414 - .) + 0
	.align	8
	.4byte	(.L168 - .) + 0
	.2byte	18
	.2byte	2
	.2byte	1
	.2byte	3
	.byte	0
	.align	8
	.4byte	(.L145 - .) + 0
	.2byte	18
	.2byte	2
	.2byte	1
	.2byte	3
	.byte	0
	.align	8
	.4byte	(.L122 - .) + 0
	.2byte	18
	.2byte	2
	.2byte	1
	.2byte	3
	.byte	0
	.align	8
	.align	4
.L411:
	.4byte	(.L416 - .) + 0
	.4byte	27789400
	.align	4
.L406:
	.4byte	(.L417 - .) + 0
	.4byte	34080976
	.align	4
.L412:
	.4byte	(.L419 - .) + 1
	.4byte	34089104
	.4byte	(.L416 - .) + -1879048192
	.4byte	26818136
	.align	4
.L410:
	.4byte	(.L416 - .) + 0
	.4byte	29383936
	.align	4
.L414:
	.4byte	(.L419 - .) + 1
	.4byte	34089104
	.4byte	(.L416 - .) + 0
	.4byte	25702864
	.align	4
.L407:
	.4byte	(.L417 - .) + 0
	.4byte	33556688
	.align	4
.L409:
	.4byte	(.L421 - .) + 1
	.4byte	14158328
	.4byte	(.L422 - .) + 1
	.4byte	17847640
	.4byte	(.L423 - .) + 1
	.4byte	19940632
	.4byte	(.L416 - .) + -1476395008
	.4byte	30542105
	.align	4
.L413:
	.4byte	(.L419 - .) + 1
	.4byte	34089104
	.4byte	(.L416 - .) + 0
	.4byte	26227200
	.align	4
.L408:
	.4byte	(.L417 - .) + 0
	.4byte	33032384
.L415:
	.ascii	"vor.ml\0"
.L420:
	.ascii	"printf.ml\0"
.L418:
	.ascii	"bytes.ml\0"
	.align	4
.L419:
	.4byte	(.L418 - .) + 0
	.ascii	"Stdlib__Bytes.init\0"
	.align	4
.L423:
	.4byte	(.L420 - .) + 0
	.ascii	"Stdlib__Printf.printf\0"
	.align	4
.L422:
	.4byte	(.L420 - .) + 0
	.ascii	"Stdlib__Printf.fprintf\0"
	.align	4
.L421:
	.4byte	(.L420 - .) + 0
	.ascii	"Stdlib__Printf.kfprintf\0"
	.align	4
.L417:
	.4byte	(.L415 - .) + 0
	.ascii	"Vor\0"
	.align	4
.L416:
	.4byte	(.L415 - .) + 0
	.ascii	"Vor.check\0"
	.align	8
	.size camlVor__frametable,. - camlVor__frametable
	.data
	.section .note.GNU-stack,"",@progbits
