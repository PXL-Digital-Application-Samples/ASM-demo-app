; CGI script to update a user
; USER_ID from environment, JSON from stdin

%include "shared.inc"

section .data
    content_type db "Content-Type: application/json", 10, 10, 0
    user_id_env db "USER_ID", 0
    not_found_msg db '{"error":"User not found"}', 10, 0
    not_found_len equ $ - not_found_msg
    error_msg db '{"error":"Invalid JSON"}', 10, 0
    error_msg_len equ $ - error_msg
    json_response_fmt db '{"id":%d,"name":"%s","email":"%s"}', 10, 0

section .bss
    input_buffer resb 1024
    name_buffer resb MAX_NAME_LEN
    email_buffer resb MAX_EMAIL_LEN
    response_buffer resb 256
    target_id resd 1
    update_flags resb 1     ; bit 0 = update name, bit 1 = update email

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
    
    ; Read JSON from stdin
    mov rax, SYS_READ
    mov rdi, 0
    mov rsi, input_buffer
    mov rdx, 1024
    syscall
    
    test rax, rax
    jle error_response
    
    ; Parse JSON (optional fields)
    mov rsi, input_buffer
    mov rdi, name_buffer
    mov rdx, email_buffer
    call parse_json_update
    mov [update_flags], al
    
    ; Get shared memory
    mov rax, SYS_SHMGET
    mov rdi, SHM_KEY
    mov rsi, SHM_SIZE
    mov rdx, 0666o
    syscall
    
    test rax, rax
    js error_response
    mov r12, rax        ; shmid
    
    ; Attach shared memory
    mov rax, SYS_SHMAT
    mov rdi, r12
    xor rsi, rsi
    xor rdx, rdx
    syscall
    
    test rax, rax
    js error_response
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
    ; Update fields based on flags
    test byte [update_flags], 1
    jz .skip_name
    
    ; Update name
    mov rsi, name_buffer
    lea rdi, [r14 + USER_NAME]
    call strcpy
    
.skip_name:
    test byte [update_flags], 2
    jz .skip_email
    
    ; Update email
    mov rsi, email_buffer
    lea rdi, [r14 + USER_EMAIL]
    call strcpy
    
.skip_email:
    ; Format response
    mov rdi, response_buffer
    mov rsi, json_response_fmt
    mov edx, [r14 + USER_ID]
    lea rcx, [r14 + USER_NAME]
    lea r8, [r14 + USER_EMAIL]
    call sprintf_simple
    
    ; Release lock
    mov dword [r13 + SHM_LOCK], 0
    
    ; Write response
    mov rax, SYS_WRITE
    mov rdi, 1
    mov rsi, response_buffer
    mov rdx, rax
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
    mov rax, SYS_WRITE
    mov rdi, 1
    mov rsi, not_found_msg
    mov rdx, not_found_len
    syscall
    
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall

error_response:
    mov rax, SYS_WRITE
    mov rdi, 1
    mov rsi, error_msg
    mov rdx, error_msg_len
    syscall
    
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall

; Parse JSON for update (fields are optional)
; Returns flags in al: bit 0 = name present, bit 1 = email present
parse_json_update:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    
    mov r12, rdi        ; name buffer
    mov r13, rdx        ; email buffer
    xor rbx, rbx        ; flags
    
    ; Clear buffers
    mov byte [r12], 0
    mov byte [r13], 0
    
    ; Skip to '{'
.skip_start:
    lodsb
    cmp al, '{'
    je .parse_loop
    test al, al
    jz .done
    jmp .skip_start
    
.parse_loop:
    ; Skip whitespace
    call skip_whitespace
    
    ; Check for end or comma
    mov al, [rsi]
    cmp al, '}'
    je .done
    cmp al, ','
    je .skip_comma
    cmp al, '"'
    jne .next_char
    
    inc rsi         ; Skip quote
    
    ; Parse field name
    mov rdi, rsi
    call find_quote
    jz .done
    
    ; Check field name
    push rsi
    mov rsi, rdi
    call check_name_field
    pop rsi
    jc .parse_name
    
    push rsi
    mov rsi, rdi
    call check_email_field
    pop rsi
    jc .parse_email
    
    ; Unknown field, skip value
    call skip_to_comma_or_brace
    jmp .parse_loop
    
.skip_comma:
    inc rsi
    jmp .parse_loop
    
.next_char:
    inc rsi
    jmp .parse_loop
    
.parse_name:
    ; Skip past ":"
    call skip_to_colon
    inc rsi
    call skip_whitespace
    
    ; Parse string value
    lodsb
    cmp al, '"'
    jne .parse_loop
    
    mov rdi, r12
    call copy_until_quote
    or rbx, 1
    jmp .parse_loop
    
.parse_email:
    ; Skip past ":"
    call skip_to_colon
    inc rsi
    call skip_whitespace
    
    ; Parse string value
    lodsb
    cmp al, '"'
    jne .parse_loop
    
    mov rdi, r13
    call copy_until_quote
    or rbx, 2
    jmp .parse_loop
    
.done:
    mov rax, rbx
    
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; Include helper functions (same as in create_user.asm)
skip_whitespace:
    push rax
.loop:
    mov al, [rsi]
    cmp al, ' '
    je .skip
    cmp al, 10
    je .skip
    cmp al, 13
    je .skip
    cmp al, 9
    je .skip
    jmp .done
.skip:
    inc rsi
    jmp .loop
.done:
    pop rax
    ret

find_quote:
    push rax
.loop:
    lodsb
    cmp al, '"'
    je .found
    test al, al
    jz .not_found
    jmp .loop
.found:
    mov rax, 1
    jmp .done
.not_found:
    xor rax, rax
.done:
    pop rax
    ret

check_name_field:
    cmp dword [rsi], 'name'
    je .found
    clc
    ret
.found:
    stc
    ret

check_email_field:
    cmp dword [rsi], 'emai'
    jne .not_found
    cmp byte [rsi+4], 'l'
    je .found
.not_found:
    clc
    ret
.found:
    stc
    ret

skip_to_colon:
    push rax
.loop:
    lodsb
    cmp al, ':'
    je .done
    test al, al
    jz .done
    jmp .loop
.done:
    dec rsi
    pop rax
    ret

skip_to_comma_or_brace:
    push rax
.loop:
    lodsb
    cmp al, ','
    je .done
    cmp al, '}'
    je .done
    test al, al
    jz .done
    jmp .loop
.done:
    dec rsi
    pop rax
    ret

copy_until_quote:
    push rax
.loop:
    lodsb
    cmp al, '"'
    je .done
    cmp al, '\\'
    je .escape
    test al, al
    jz .done
    stosb
    jmp .loop
.escape:
    lodsb
    stosb
    jmp .loop
.done:
    mov byte [rdi], 0
    pop rax
    ret

strcpy:
    push rdi
.loop:
    lodsb
    stosb
    test al, al
    jnz .loop
    pop rdi
    ret

; Include getenv_simple and other functions
getenv_simple:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    
    mov r12, rdi
    mov rax, [rsp + 24]
    lea rbx, [rsp + 32]
    
.skip_argv:
    mov rax, [rbx]
    add rbx, 8
    test rax, rax
    jnz .skip_argv
    
.check_env:
    mov r13, [rbx]
    test r13, r13
    jz .not_found
    
    mov rsi, r12
    mov rdi, r13
    call strncmp_until_equals
    test rax, rax
    jz .found
    
    add rbx, 8
    jmp .check_env
    
.found:
    mov rax, r13
.find_equals:
    cmp byte [rax], '='
    je .got_equals
    inc rax
    jmp .find_equals
    
.got_equals:
    inc rax
    jmp .done
    
.not_found:
    xor rax, rax
    
.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

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

sprintf_simple:
    push rbp
    mov rbp, rsp
    push rdi
    
    mov byte [rdi], '{'
    mov byte [rdi+1], '"'
    mov byte [rdi+2], 'i'
    mov byte [rdi+3], 'd'
    mov byte [rdi+4], '"'
    mov byte [rdi+5], ':'
    add rdi, 6
    
    push rcx
    push r8
    mov eax, edx
    call int_to_str
    pop r8
    pop rcx
    
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
    
    mov rsi, rcx
.copy_name:
    lodsb
    test al, al
    jz .name_done
    stosb
    jmp .copy_name
    
.name_done:
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
    
    mov rsi, r8
.copy_email:
    lodsb
    test al, al
    jz .email_done
    stosb
    jmp .copy_email
    
.email_done:
    mov byte [rdi], '"'
    mov byte [rdi+1], '}'
    add rdi, 2
    
    pop rax
    sub rdi, rax
    mov rax, rdi
    
    pop rbp
    ret

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