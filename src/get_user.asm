; CGI script to get a specific user by ID
; USER_ID environment variable contains the ID

%include "shared.inc"

section .data
    content_type db "Content-Type: application/json", 10, 10, 0
    user_id_env db "USER_ID", 0
    not_found_msg db '{"error":"User not found"}', 10, 0
    not_found_len equ $ - not_found_msg
    json_user_fmt db '{"id":%d,"name":"%s","email":"%s"}', 10, 0

section .bss
    user_id_str resb 16
    user_json resb 256
    target_id resd 1

section .text
global _start

extern getenv

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
    mov r14, [r13 + SHM_HEAD]
    
.search_loop:
    test r14, r14
    jz .not_found_unlock
    
    mov eax, [r14 + USER_ID]
    cmp eax, [target_id]
    je .found
    
    mov r14, [r14 + USER_NEXT]
    jmp .search_loop
    
.found:
    ; Format user as JSON
    mov rdi, user_json
    mov rsi, json_user_fmt
    mov edx, [r14 + USER_ID]
    lea rcx, [r14 + USER_NAME]
    lea r8, [r14 + USER_EMAIL]
    call sprintf_simple
    
    ; Release lock
    mov dword [r13 + SHM_LOCK], 0
    
    ; Write response
    mov rax, SYS_WRITE
    mov rdi, 1
    mov rsi, user_json
    mov rdx, rax        ; sprintf returns length
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
; rdi = env var name
; Returns pointer in rax or 0
getenv_simple:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    
    mov r12, rdi        ; Save var name
    
    ; Get environ pointer
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
    ; Check if second string ended
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
; rsi = string
; Returns in eax
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

; Include sprintf_simple from list_users
sprintf_simple:
    push rbp
    mov rbp, rsp
    push rdi
    
    ; Start with '{"id":'
    mov byte [rdi], '{'
    mov byte [rdi+1], '"'
    mov byte [rdi+2], 'i'
    mov byte [rdi+3], 'd'
    mov byte [rdi+4], '"'
    mov byte [rdi+5], ':'
    add rdi, 6
    
    ; Convert ID to string
    push rcx
    push r8
    mov eax, edx
    call int_to_str
    pop r8
    pop rcx
    
    ; Add ',"name":"'
    mov byte [rdi], ','
    mov byte [rdi+1], '"'
    mov byte [rdi+2], 'n'
    mov byte [rdi+3], 'a'
    mov byte [rdi+4], 'm'
    mov byte [rdi+5], 'e'
    mov byte [rdi+6], '"'
    mov byte [rdi+7], ':'
    mov byte [rdi+8], '"'
    add rdi, 9
    
    ; Copy name
    mov rsi, rcx
.copy_name:
    lodsb
    test al, al
    jz .name_done
    stosb
    jmp .copy_name
    
.name_done:
    ; Add '","email":"'
    mov byte [rdi], '"'
    mov byte [rdi+1], ','
    mov byte [rdi+2], '"'
    mov byte [rdi+3], 'e'
    mov byte [rdi+4], 'm'
    mov byte [rdi+5], 'a'
    mov byte [rdi+6], 'i'
    mov byte [rdi+7], 'l'
    mov byte [rdi+8], '"'
    mov byte [rdi+9], ':'
    mov byte [rdi+10], '"'
    add rdi, 11
    
    ; Copy email
    mov rsi, r8
.copy_email:
    lodsb
    test al, al
    jz .email_done
    stosb
    jmp .copy_email
    
.email_done:
    ; Add '"}'
    mov byte [rdi], '"'
    mov byte [rdi+1], '}'
    add rdi, 2
    
    ; Calculate length
    pop rax         ; Original buffer
    sub rdi, rax
    mov rax, rdi
    
    pop rbp
    ret

; Convert integer to string
int_to_str:
    push rbx
    push rdx
    mov ebx, 10
    xor rcx, rcx
    
.divide:
    xor edx, edx
    div ebx
    push rdx
    inc rcx
    test eax, eax
    jnz .divide
    
.write:
    pop rax
    add al, '0'
    stosb
    loop .write
    
    pop rdx
    pop rbx
    ret