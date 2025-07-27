; Initialize shared memory with seed data
; nasm -f elf64 init_shm.asm && ld -o init_shm init_shm.o

%include "shared.inc"

section .data
    msg_init db "Initializing shared memory...", 10, 0
    msg_init_len equ $ - msg_init
    
    ; Seed users
    user1_name db "Alice", 0
    user1_email db "alice@example.com", 0
    
    user2_name db "Bob", 0
    user2_email db "bob@example.com", 0
    
    user3_name db "Charlie", 0
    user3_email db "charlie@example.com", 0

section .text
global _start

_start:
    ; Print init message
    mov rax, SYS_WRITE
    mov rdi, 1
    mov rsi, msg_init
    mov rdx, msg_init_len
    syscall
    
    ; Create/get shared memory
    mov rax, SYS_SHMGET
    mov rdi, SHM_KEY
    mov rsi, SHM_SIZE
    mov rdx, IPC_CREAT | 0666o
    syscall
    
    test rax, rax
    js exit_error
    mov r12, rax        ; Save shmid
    
    ; Attach shared memory
    mov rax, SYS_SHMAT
    mov rdi, r12
    xor rsi, rsi
    xor rdx, rdx
    syscall
    
    test rax, rax
    js exit_error
    mov r13, rax        ; Save shm address
    
    ; Initialize header
    mov dword [r13 + SHM_LOCK], 0      ; Lock = 0
    mov dword [r13 + SHM_NEXT_ID], 4   ; Next ID = 4
    mov qword [r13 + SHM_HEAD], 0      ; Head = NULL
    
    ; Add seed users
    mov rdi, 1
    mov rsi, user1_name
    mov rdx, user1_email
    call add_user
    
    mov rdi, 2
    mov rsi, user2_name
    mov rdx, user2_email
    call add_user
    
    mov rdi, 3
    mov rsi, user3_name
    mov rdx, user3_email
    call add_user
    
    ; Detach shared memory
    mov rax, SYS_SHMDT
    mov rdi, r13
    syscall
    
    ; Exit success
    xor rdi, rdi
    mov rax, SYS_EXIT
    syscall

exit_error:
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall

; Add user to linked list
; rdi = id, rsi = name ptr, rdx = email ptr
add_user:
    push rbp
    mov rbp, rsp
    push r14
    push r15
    
    ; Calculate next free position
    mov rax, [r13 + SHM_HEAD]
    test rax, rax
    jz .first_user
    
    ; Find last user
    mov r14, rax
.find_last:
    mov rax, [r14 + USER_NEXT]
    test rax, rax
    jz .found_last
    mov r14, rax
    jmp .find_last
    
.found_last:
    ; Calculate position after last user
    lea r15, [r14 + USER_SIZE]
    jmp .create_user
    
.first_user:
    ; First user goes at SHM_FREE_SPACE
    lea r15, [r13 + SHM_FREE_SPACE]
    
.create_user:
    ; Set user fields
    mov dword [r15 + USER_ID], edi
    mov qword [r15 + USER_NEXT], 0
    
    ; Copy name
    lea rdi, [r15 + USER_NAME]
    call strcpy
    
    ; Copy email
    mov rsi, rdx
    lea rdi, [r15 + USER_EMAIL]
    call strcpy
    
    ; Update linked list
    mov rax, [r13 + SHM_HEAD]
    test rax, rax
    jnz .not_first
    
    ; First user
    mov [r13 + SHM_HEAD], r15
    jmp .done
    
.not_first:
    ; Link from last user
    mov [r14 + USER_NEXT], r15
    
.done:
    pop r15
    pop r14
    pop rbp
    ret

; Simple string copy
; rdi = dest, rsi = src
strcpy:
    push rdi
.loop:
    lodsb
    stosb
    test al, al
    jnz .loop
    pop rdi
    ret