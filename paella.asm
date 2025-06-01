	.globl _fib
_fib:
	pushq   %rbp
	movq    %rsp, %rbp
	subq    $48, %rsp
	movl    %edi, -4(%rsp)
	cmpl    $0, -4(%rsp)
	movl    $0, -8(%rsp)
	sete      -8(%rsp)
	cmpl    $0, -8(%rsp)
	jne     .Ltrue_or.2
	cmpl    $1, -4(%rsp)
	movl    $0, -12(%rsp)
	sete      -12(%rsp)
	cmpl    $0, -12(%rsp)
	jne     .Ltrue_or.2
	movl    $0, -16(%rsp)
	jmp    .Lend_or.3
.Ltrue_or.2:
	movl    $1, -16(%rsp)
.Lend_or.3:
	cmpl    $0, -16(%rsp)
	je      .Lelse.7
	movl    -4(%rsp), %eax
	movq    %rbp, %rsp
	popq    %rbp
	ret
	jmp    .Lend.8
.Lelse.7:
	movl    -4(%rsp), %r10d
	movl    %r10d, -20(%rsp)
	subl    $1, -20(%rsp)
	movl    -20(%rsp), %edi
	call    _fib
	movl    %eax, -24(%rsp)
	movl    -4(%rsp), %r10d
	movl    %r10d, -28(%rsp)
	subl    $2, -28(%rsp)
	movl    -28(%rsp), %edi
	call    _fib
	movl    %eax, -32(%rsp)
	movl    -24(%rsp), %r10d
	movl    %r10d, -36(%rsp)
	movl    -32(%rsp), %r10d
	addl    %r10d, -36(%rsp)
	movl    -36(%rsp), %eax
	movq    %rbp, %rsp
	popq    %rbp
	ret
.Lend.8:
	movl    $0, %eax
	movq    %rbp, %rsp
	popq    %rbp
	ret
	.globl _main
_main:
	pushq   %rbp
	movq    %rsp, %rbp
	subq    $16, %rsp
	movl    $6, -4(%rsp)
	movl    -4(%rsp), %edi
	call    _fib
	movl    %eax, -8(%rsp)
	movl    -8(%rsp), %eax
	movq    %rbp, %rsp
	popq    %rbp
	ret
	movl    $0, %eax
	movq    %rbp, %rsp
	popq    %rbp
	ret
