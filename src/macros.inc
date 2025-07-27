; NASM Macros for cleaner code

; Write a string literal to memory at current position
; Usage: WRITE_STRING "hello", rdi
%macro WRITE_STRING 2
    %strlen %%len %1
    %assign %%i 0
    %rep %%len
        %substr %%char %1 %%i+1
        mov byte [%2 + %%i], %%char
        %assign %%i %%i+1
    %endrep
%endmacro

; Write a string literal and advance pointer
; Usage: APPEND_STRING "hello", rdi
%macro APPEND_STRING 2
    WRITE_STRING %1, %2
    %strlen %%len %1
    add %2, %%len
%endmacro

; System call wrapper for better readability
; Usage: SYSCALL write, 1, message, message_len
%macro SYSCALL 2-4
    %if %0 == 2
        mov rax, SYS_%1
        mov rdi, %2
    %elif %0 == 3
        mov rax, SYS_%1
        mov rdi, %2
        mov rsi, %3
    %elif %0 == 4
        mov rax, SYS_%1
        mov rdi, %2
        mov rsi, %3
        mov rdx, %4
    %endif
    syscall
%endmacro

; Acquire spinlock with label
; Usage: ACQUIRE_LOCK r13, SHM_LOCK
%macro ACQUIRE_LOCK 2
%%acquire:
    mov eax, 1
    xchg eax, [%1 + %2]
    test eax, eax
    jnz %%acquire
%endmacro

; Release spinlock
; Usage: RELEASE_LOCK r13, SHM_LOCK
%macro RELEASE_LOCK 2
    mov dword [%1 + %2], 0
%endmacro

; Write HTTP response header
%macro HTTP_JSON_HEADER 0
    SYSCALL WRITE, 1, content_type, 32
%endmacro

; Write JSON error response
; Usage: JSON_ERROR "User not found"
%macro JSON_ERROR 1
    section .data
    %%msg db '{"error":"', %1, '"}', 10, 0
    %%len equ $ - %%msg
    section .text
    SYSCALL WRITE, 1, %%msg, %%len
%endmacro

; Define a constant string
; Usage: CONST_STRING greeting, "Hello, World!"
%macro CONST_STRING 2
    section .data
    %1 db %2, 0
    %1_len equ $ - %1
    section .text
%endmacro

; Save all caller-saved registers
%macro SAVE_REGS 0
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
%endmacro

; Restore all caller-saved registers
%macro RESTORE_REGS 0
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
%endmacro

; Compare string with immediate
; Sets ZF if equal
; Usage: CMP_STRING rsi, "name"
%macro CMP_STRING 2
    push rsi
    push rax
    %strlen %%len %2
    %assign %%i 0
    %rep %%len
        %substr %%char %2 %%i+1
        lodsb
        cmp al, %%char
        jne %%not_equal
        %assign %%i %%i+1
    %endrep
    xor rax, rax    ; Set ZF
    jmp %%done
%%not_equal:
    or rax, 1       ; Clear ZF
%%done:
    pop rax
    pop rsi
%endmacro

; Debug print macro (writes to stderr)
; Usage: DEBUG "checkpoint reached"
%macro DEBUG 1
    %ifdef DEBUG_MODE
    section .data
    %%msg db "[DEBUG] ", %1, 10, 0
    %%len equ $ - %%msg
    section .text
    push rax
    push rdi
    push rsi
    push rdx
    SYSCALL WRITE, 2, %%msg, %%len
    pop rdx
    pop rsi
    pop rdi
    pop rax
    %endif
%endmacro