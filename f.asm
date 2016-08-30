BITS 64

sys_read EQU 0
sys_write EQU 1

SECTION .bss
        buf RESB 8192
        buflen EQU $-buf

        stack RESB 100000
        continuationstack RESB 100000

SECTION .data
program:
        DQ stdexe
        DQ LIT
        DQ 314592
        DQ DOT
        DQ NEXTWORD

ipl:    DQ stdexe
        DQ program
        DQ EXIT

LIT:
        DQ implit
ZEROBRANCH:
        DQ impzerobranch
BRANCH:
        DQ impbranch
SWAP:
        DQ impswap
DUP:
        DQ impdup
OVER:
        DQ impover
DROP:
        DQ impdrop
EQ0:
        DQ impeq0
LT:
        DQ implt
ADD:
        DQ impadd
CSTORE:
        DQ impcstore
DOT:
; Observation: It is easy to calculate the least significant digit,
; by dividing by 10 and taking the remainder.
; We proceed by pushing the digits onto the stack,
; pushing the least significant first.
; This creates a stack of digits of variable length;
; we mark the beginning of the stack of digits with
; a sentinel value, which is 99 (which can't possible be a digit).
        DQ stdexe
        DQ LIT
        DQ 99
        DQ SWAP
.10div: DQ LIT
        DQ 10
        DQ DIVMOD       ; -- Q R
        DQ SWAP         ; -- R Q
        DQ DUP          ; -- R Q Q
        DQ EQ0          ; -- R Q flag
        DQ ZEROBRANCH   ; -- R Q
        DQ -(($-.10div)/8) - 1
        DQ DROP
        ; stack now contains the digits
        DQ BUF
.pop:   DQ SWAP         ; buf d
        DQ DUP          ; buf d d
        DQ LIT
        DQ 10           ; buf d d 10
        DQ LT           ; buf d flag
        DQ ZEROBRANCH   ; buf d
        DQ (.write-$)/8 - 1
        DQ LIT
        DQ 48           ; buf d 48
        DQ ADD          ; buf ch
        DQ OVER         ; buf ch buf
        DQ CSTORE       ; buf
        DQ LIT
        DQ 1            ; buf 1
        DQ ADD          ; buf+1
        DQ BRANCH
        DQ -(($-.pop)/8) - 1
.write: DQ DROP         ; buf
        DQ LIT
        DQ 10           ; buf 10
        DQ OVER         ; buf 10 buf
        DQ CSTORE       ; buf
        DQ LIT
        DQ 1            ; buf 1
        DQ ADD          ; buf+1
        DQ restofDOT
        DQ NEXTWORD
restofDOT:
        DQ imprestofdot
DIVMOD:
        DQ impdivmod
EXIT:
        DQ impexit
NEXTWORD:
        DQ impnextword

BUF:
        DQ impbuf


SECTION .text
GLOBAL _start
_start:
        ; Initialise the model registers.
        mov r8, stack
        mov r10, continuationstack
        ; Initialising RDX and R9, so as to fake
        ; executing the Forth word IPL.
        mov rdx, program
        mov r9, ipl+16

stdexe:
        mov [r10], r9
        add r10, 8
        lea r9, [rdx+8]
next:
        mov rdx, [r9]
        add r9, 8
        mov rbp, [rdx]
        jmp rbp

;;; Machine code implementations of various Forth words.

impnextword:
        sub r10, 8
        mov r9, [r10]
        jmp next

implit:
        mov rax, [r9]
        add r9, 8
        mov [r8], rax
        add r8, 8
        jmp next

impzerobranch:
        ; read the next word as a relative offset;
        ; pop the TOS and test it;
        ; if it is 0 then branch by adding the offset
        ; to CODEPOINTER.
        mov rbx, [r9]
        add r9, 8
        sub r8, 8
        mov rax, [r8]
        test rax, rax
        jnz next
        lea r9, [r9 + 8*rbx]
        jmp next
impbranch:
        ; read the next word as a relative offset;
        ; branch by adding offset to CODEPOINTER.
        mov rbx, [r9]
        add r9, 8
        lea r9, [r9 + 8*rbx]
        jmp next

impswap:
        ; SWAP (A B -- B A)
        mov rbp, [r8-16]
        mov rdx, [r8-8]
        mov [r8-16], rdx
        mov [r8-8], rbp
        jmp next
impdup:
        ; DUP (A -- A A)
        mov rdx, [r8-8]
        mov [r8], rdx
        add r8, 8
        jmp next
impover:
        ; OVER (A B -- A B A)
        mov rax, [r8-16]
        mov [r8], rax
        add r8, 8
        jmp next
impdrop:
        ; DROP (A -- )
        sub r8, 8
        jmp next
impeq0:        ; this needs inverting (and stack is all wrong)
        ; EQ0 (A -- Bool)
        ; Result is -1 (TRUE) if A = 0;
        ; Result is 0 (FALSE) otherwise.
        mov rax, [r8-8]
        sub rax, 1      ; is-zero now in Carry flag
        sbb rax, rax    ; C=0 -> 0; C=1 -> -1
        mov [r8-8], rax
        jmp next
implt:
        ; < (A B -- flag)
        ; flag is -1 (TRUE) if A < B;
        mov rax, [r8-16]
        mov rbx, [r8-8]
        sub r8, 16
        cmp rax, rbx    ; C iff B > A
        sbb rax, rax    ; -1 iff B > A
        mov [r8], rax
        add r8, 8
        jmp next
impadd:
        ; + (A B -- sum)
        mov rax, [r8-16]
        mov rbx, [r8-8]
        add rax, rbx
        sub r8, 8
        mov [r8-8], rax
        jmp next
impcstore:
        ; C! (ch buf -- )
        mov rax, [r8-16]
        mov rdx, [r8-8]
        sub r8, 16
        mov [rdx], al
        jmp next

impexit:
        mov rdi, 0
        mov rax, 60
        syscall

impdivmod:      ; /MOD (dividend divisor -- quotient remainder)
        ; > RCX
        sub r8, 8
        mov rcx, [r8]
        ; > RAX
        sub r8, 8
        mov rax, [r8]

        mov rdx, 0
        idiv rcx

        ; RAX >
        mov [r8], rax
        add r8, 8
        ; RDX >
        mov [r8], rdx
        add r8, 8
        jmp next

imprestofdot: ; ( PTR -- )
        ; write contents of buffer to stdout
        mov rdx, [r8-8]
        sub rdx, buf    ; the buffer length
        mov rdi, 1      ; stdout
        mov rsi, buf
        mov rax, sys_write
        syscall
        jmp next

impbuf:
        mov rdx, buf
        mov [r8], rdx
        add r8, 8
        jmp next
