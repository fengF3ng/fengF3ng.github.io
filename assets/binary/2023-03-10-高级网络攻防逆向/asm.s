	.file	"test.c"
	.text
	.comm	a,4,4
	.section	.rodata
.LC2:
	.string	"you win"
.LC3:
	.string	"you lose"
	.text
	.globl	main
	.type	main, @function
main:
.LFB0:
	.cfi_startproc
	endbr64
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset 6, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register 6
	subq	$16, %rsp
	movl	$97, -16(%rbp)
	movss	.LC0(%rip), %xmm0
	movss	%xmm0, -12(%rbp)
	movl	$4, -8(%rbp)
	movss	.LC1(%rip), %xmm0
	movss	%xmm0, -4(%rbp)
	movss	-4(%rbp), %xmm0
	addss	-12(%rbp), %xmm0
	movss	%xmm0, -4(%rbp)
	movl	-8(%rbp), %eax
	movl	$97, %edx
	movl	%eax, %ecx
	sall	%cl, %edx
	movl	%edx, %eax
	sall	$3, %eax
	addl	%edx, %eax
	addl	%eax, %eax
	addl	%eax, %edx
	movl	a(%rip), %eax
	cmpl	%eax, %edx
	jne	.L2
	leaq	.LC2(%rip), %rdi
	call	puts@PLT
	jmp	.L4
.L2:
	leaq	.LC3(%rip), %rdi
	call	puts@PLT
.L4:
	nop
	leave
	.cfi_def_cfa 7, 8
	ret
	.cfi_endproc
.LFE0:
	.size	main, .-main
	.section	.rodata
	.align 4
.LC0:
	.long	1068289229
	.align 4
.LC1:
	.long	1089113948
	.ident	"GCC: (Ubuntu 9.4.0-1ubuntu1~20.04.1) 9.4.0"
	.section	.note.GNU-stack,"",@progbits
	.section	.note.gnu.property,"a"
	.align 8
	.long	 1f - 0f
	.long	 4f - 1f
	.long	 5
0:
	.string	 "GNU"
1:
	.align 8
	.long	 0xc0000002
	.long	 3f - 2f
2:
	.long	 0x3
3:
	.align 8
4:
