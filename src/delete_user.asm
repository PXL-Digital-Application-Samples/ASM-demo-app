; CGI script to delete a user by ID
; USER_ID environment variable contains the ID

%include "shared.inc"

section .data
    content_type db "Content-Type: application/json", 10, 10, 0
    user_id_env db "USER_ID", 0
    not_found_msg db '{"error":"User not found"}', 10, 0
    not_found_len equ $ - not_found_msg
    success_msg db '{"message":"User deleted"}', 10, 0
    success_len equ $ - success_msg

section .bss
    target_id resd 1

section .text
global _start

_start:
    ; Write HTTP headers
    mov rax, SYS_WRITE
    mov rdi, 1
    mov rsi, content_type
    mov rdx, 32
    syscall
    
    ; Get USER_ID from environment
    mov rdi, user_id_env
    call getenv_simple
    test rax, rax
    jz not_found
    
    ; Convert to integer
    mov rsi, rax
    call str_to_int
    mov [target_id], eax
    
    ; Get shared memory
    mov rax, SYS_SHMGET
    mov rdi, SHM_KEY
    mov rsi, SHM_SIZE
    mov rdx, 0666o
    syscall
    
    test rax, rax
    js not_found
    mov r12, rax        ; shmid
    
    ; Attach shared memory
    mov rax, SYS_SHMAT
    mov rdi, r12
    xor rsi, rsi
    xor rdx, rdx
    syscall
    
    test rax, rax
    js not_found
    mov r13, rax        ; shm address
    
    ; Acquire lock
.acquire_lock:
    mov eax, 1
    xchg eax, [r13 + SHM_LOCK]
    test eax, eax
    jnz .acquire_lock
    
    ; Search for user
    mov r14, [r13 + SHM_HEAD]   ; Current
    xor r15, r15                 ; Previous
    
.search_loop:
    test r14, r14
    jz .not_found_unlock
    
    mov eax, [r14 + USER_ID]
    cmp eax, [target_id]
    je .found
    
    mov r15, r14                ; Previous = current
    mov r14, [r14 + USER_NEXT]  ; Current = next
    jmp .search_loop
    
.found:
    ; Remove from linked list
    mov rax, [r14 + USER_NEXT]  ; Get next pointer
    
    test r15, r15
    jz .delete_head
    
    ; Not head, update previous
    mov [r15 + USER_NEXT], rax
    jmp .done_delete
    
.delete_head:
    ; Update head
    mov [r13 + SHM_HEAD], rax
    
.done_delete:
    ; Clear user data (optional, but good practice)
    mov rdi, r14
    xor rax, rax
    mov rcx, USER_SIZE / 8
    rep stosq
    
    ; Release lock
    mov dword [r13 + SHM_LOCK], 0
    
    ; Write success response
    mov rax, SYS_WRITE
    mov rdi, 1
    mov rsi, success_msg
    mov rdx, success_len
    syscall
    
    ; Detach and exit
    mov rax, SYS_SHMDT
    mov rdi, r13
    syscall
    
    xor rdi, rdi
    mov rax, SYS_EXIT
    syscall
    
.not_found_unlock:
    ; Release lock
    mov dword [r13 + SHM_LOCK], 0
    
    ; Detach
    mov rax, SYS_SHMDT
    mov rdi, r13
    syscall
    
not_found:
    ; Write not found response
    mov rax, SYS_WRITE
    mov rdi, 1
    mov rsi, not_found_msg
    mov rdx, not_found_len
    syscall
    
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall

; Simple getenv implementation
getenv_simple:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    
    mov r12, rdi        ; Save var name
    
    ; Get environ pointer from stack
    mov rax, [rsp + 24] ; argc
    lea rbx, [rsp + 32] ; argv
    
    ; Skip past argv
.skip_argv:
    mov rax, [rbx]
    add rbx, 8
    test rax, rax
    jnz .skip_argv
    
    ; rbx now points to environ
.check_env:
    mov r13, [rbx]
    test r13, r13
    jz .not_found
    
    ; Compare with our variable
    mov rsi, r12
    mov rdi, r13
    call strncmp_until_equals
    test rax, rax
    jz .found
    
    add rbx, 8
    jmp .check_env
    
.found:
    ; Return pointer after '='
    mov rax, r13
.find_equals:
    cmp byte [rax], '='
    je .got_equals
    inc rax
    jmp .find_equals
    
.got_equals:
    inc rax         ; Skip '='
    jmp .done
    
.not_found:
    xor rax, rax
    
.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; Compare strings until '=' in first string
strncmp_until_equals:
    push rsi
    push rdi
    
.loop:
    mov al, [rdi]
    cmp al, '='
    je .check_end
    
    cmp al, [rsi]
    jne .not_equal
    
    test al, al
    jz .equal
    
    inc rdi
    inc rsi
    jmp .loop
    
.check_end:
    cmp byte [rsi], 0
    je .equal
    
.not_equal:
    mov rax, 1
    jmp .done
    
.equal:
    xor rax, rax
    
.done:
    pop rdi
    pop rsi
    ret

; Convert string to integer
str_to_int:
    xor eax, eax
    xor ecx, ecx
    
.loop:
    movzx ecx, byte [rsi]
    test cl, cl
    jz .done
    cmp cl, '0'
    jb .done
    cmp cl, '9'
    ja .done
    
    sub cl, '0'
    imul eax, 10
    add eax, ecx
    inc rsi
    jmp .loop
    
.done:
    ret