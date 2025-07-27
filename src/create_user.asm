; CGI script to create a new user
; Reads JSON from stdin in format: {"name":"...","email":"..."}
; Returns created user with assigned ID
;
; Flow:
; 1. Read JSON from stdin
; 2. Parse name and email fields
; 3. Lock shared memory
; 4. Allocate new user at end of linked list
; 5. Assign next ID and increment counter
; 6. Return new user as JSON

%include "shared.inc"

section .data
    ; HTTP header
    content_type db "Content-Type: application/json", 10, 10, 0
    
    ; String constants for JSON parsing
    name_field db "name", 0
    email_field db "email", 0

section .bss
    input_buffer resb 1024          ; Raw JSON input
    name_buffer resb MAX_NAME_LEN   ; Extracted name
    email_buffer resb MAX_EMAIL_LEN ; Extracted email  
    response_buffer resb 256        ; JSON response
    new_id resd 1                   ; ID for new user

section .text
global _start

_start:
    ; === Send HTTP headers ===
    HTTP_JSON_HEADER
    
    ; === Read JSON request body from stdin ===
    SYSCALL READ, 0, input_buffer, 1024
    
    test rax, rax               ; Check if we got any data
    jle .error_invalid_json     ; No data = error
    
    ; === Parse JSON input ===
    mov rsi, input_buffer       ; Source: raw JSON
    mov rdi, name_buffer        ; Dest: name field
    mov rdx, email_buffer       ; Dest: email field
    call parse_user_json
    
    test rax, rax               ; Check parse result
    jz .error_invalid_json      ; Failed parse = error
    
    ; === Connect to shared memory ===
    SYSCALL SHMGET, SHM_KEY, SHM_SIZE, 0666o
    test rax, rax
    js .error_invalid_json
    mov r12, rax                ; r12 = shmid
    
    ; Attach shared memory
    SYSCALL SHMAT, r12
    xor rsi, rsi
    xor rdx, rdx
    syscall
    
    test rax, rax
    js .error_invalid_json
    mov r13, rax                ; r13 = shm base address
    
    ; === Lock shared memory for exclusive access ===
    ACQUIRE_LOCK r13, SHM_LOCK
    
    ; === Allocate ID and find insertion point ===
    ; Get next ID and increment counter atomically
    mov eax, [r13 + SHM_NEXT_ID]
    mov [new_id], eax           ; Save our ID
    inc eax
    mov [r13 + SHM_NEXT_ID], eax ; Update next ID
    
    ; === Find end of linked list ===
    mov r14, [r13 + SHM_HEAD]   ; r14 = current node
    test r14, r14
    jz .first_user              ; Empty list case
    
    ; Traverse to find last user
    mov r15, r14                ; r15 = previous node
.find_last:
    mov rax, [r15 + USER_NEXT]
    test rax, rax
    jz .found_last              ; Found end when next = NULL
    mov r15, rax                ; Move to next
    jmp .find_last
    
.found_last:
    ; New user goes after the last user
    lea r14, [r15 + USER_SIZE]  ; r14 = address for new user
    jmp .create_user
    
.first_user:
    ; First user goes at start of free space
    lea r14, [r13 + SHM_FREE_SPACE]
    
.create_user:
    ; === Initialize user structure ===
    ; Set ID
    mov eax, [new_id]
    mov [r14 + USER_ID], eax
    
    ; Clear next pointer
    mov qword [r14 + USER_NEXT], 0
    
    ; Copy name using optimized string copy
    mov rsi, name_buffer
    lea rdi, [r14 + USER_NAME]
    call strcpy_safe            ; Safe copy with bounds checking
    
    ; Copy email
    mov rsi, email_buffer
    lea rdi, [r14 + USER_EMAIL]
    call strcpy_safe
    
    ; === Update linked list pointers ===
    mov rax, [r13 + SHM_HEAD]
    test rax, rax
    jnz .not_first
    
    ; First user - update head
    mov [r13 + SHM_HEAD], r14
    jmp .list_updated
    
.not_first:
    ; Link from previous user
    mov [r15 + USER_NEXT], r14
    
.list_updated:
    ; === Release lock ===
    RELEASE_LOCK r13, SHM_LOCK
    
    ; === Format and send response ===
    mov rdi, response_buffer
    mov edx, [new_id]
    mov rcx, name_buffer
    mov r8, email_buffer
    call format_user_json
    
    ; Write response
    SYSCALL WRITE, 1, response_buffer, rax
    
    ; === Cleanup ===
    SYSCALL SHMDT, r13          ; Detach shared memory
    SYSCALL EXIT, 0             ; Success

.error_invalid_json:
    JSON_ERROR "Invalid JSON or name/email required"
    SYSCALL EXIT, 1

; ===================================================================
; parse_user_json - Extract name and email from JSON
; Input:
;   rsi = JSON string pointer
;   rdi = name buffer (output)
;   rdx = email buffer (output)
; Output:
;   rax = 1 on success, 0 on failure
;
; Expects JSON format: {"name":"value","email":"value"}
; ===================================================================
parse_user_json:
    push rbp
    mov rbp, rsp
    SAVE_REGS
    
    mov r12, rdi                ; r12 = name buffer
    mov r13, rdx                ; r13 = email buffer
    xor rbx, rbx                ; rbx = found flags (bit 0=name, bit 1=email)
    
    ; Clear output buffers
    mov byte [r12], 0
    mov byte [r13], 0
    
    ; Skip to opening brace
    call skip_whitespace
    lodsb
    cmp al, '{'
    jne .fail
    
.parse_field:
    call skip_whitespace
    
    ; Check for end of object or comma
    mov al, [rsi]
    cmp al, '}'
    je .check_complete
    cmp al, ','
    jne .parse_key
    inc rsi                     ; Skip comma
    jmp .parse_field
    
.parse_key:
    ; Expect opening quote
    lodsb
    cmp al, '"'
    jne .fail
    
    ; Check if key is "name" or "email"
    mov rdi, rsi                ; Save key start
    call skip_to_quote          ; Find closing quote
    
    ; Compare key with "name"
    push rsi
    mov rsi, rdi
    mov rdi, name_field
    call strcmp_n               ; Compare n chars
    pop rsi
    jc .is_name_field
    
    ; Compare key with "email"
    push rsi
    mov rsi, rdi
    mov rdi, email_field
    call strcmp_n
    pop rsi
    jc .is_email_field
    
    ; Unknown field - skip the value
    call skip_field_value
    jmp .parse_field
    
.is_name_field:
    mov rdi, r12                ; Target = name buffer
    or rbx, 1                   ; Set name found flag
    jmp .parse_value
    
.is_email_field:
    mov rdi, r13                ; Target = email buffer
    or rbx, 2                   ; Set email found flag
    
.parse_value:
    ; Skip past closing quote and colon
    call skip_to_colon
    inc rsi                     ; Skip colon
    call skip_whitespace
    
    ; Expect value quote
    lodsb
    cmp al, '"'
    jne .fail
    
    ; Copy value until closing quote
    call copy_quoted_string
    jmp .parse_field
    
.check_complete:
    ; Both name and email must be present
    cmp rbx, 3                  ; Both flags set?
    je .success
    
.fail:
    xor rax, rax
    jmp .done
    
.success:
    mov rax, 1
    
.done:
    RESTORE_REGS
    pop rbp
    ret

; ===================================================================
; Helper functions for JSON parsing
; ===================================================================

; Skip whitespace characters
skip_whitespace:
    push rax
.loop:
    mov al, [rsi]
    cmp al, ' '
    je .skip
    cmp al, 9                   ; Tab
    je .skip
    cmp al, 10                  ; LF
    je .skip
    cmp al, 13                  ; CR
    je .skip
    jmp .done
.skip:
    inc rsi
    jmp .loop
.done:
    pop rax
    ret

; Skip to next quote character
skip_to_quote:
    push rax
.loop:
    lodsb
    cmp al, '"'
    je .done
    test al, al
    jz .done
    jmp .loop
.done:
    pop rax
    ret

; Skip to colon character
skip_to_colon:
    push rax
.loop:
    lodsb
    cmp al, ':'
    je .found
    test al, al
    jz .done
    jmp .loop
.found:
    dec rsi                     ; Back up to colon
.done:
    pop rax
    ret

; Copy quoted string to buffer
; rsi = source (after opening quote)
; rdi = destination buffer
copy_quoted_string:
    push rax
    push rcx
    xor rcx, rcx                ; Character count
    
.loop:
    lodsb
    cmp al, '"'                 ; End quote?
    je .done
    cmp al, '\'                 ; Escape char?
    je .escape
    test al, al                 ; Null terminator?
    jz .done
    
    ; Copy character if within bounds
    cmp rcx, MAX_NAME_LEN-1     ; Leave room for null
    jae .loop                   ; Skip if buffer full
    
    stosb
    inc rcx
    jmp .loop
    
.escape:
    lodsb                       ; Get escaped character
    cmp rcx, MAX_NAME_LEN-1
    jae .loop
    stosb
    inc rcx
    jmp .loop
    
.done:
    mov byte [rdi], 0           ; Null terminate
    pop rcx
    pop rax
    ret

; Skip over a field value (for unknown fields)
skip_field_value:
    call skip_to_colon
    inc rsi
    call skip_whitespace
    
    mov al, [rsi]
    cmp al, '"'                 ; String value?
    je .skip_string
    
    ; Skip non-string value
.skip_simple:
    lodsb
    cmp al, ','
    je .done
    cmp al, '}'
    je .done
    test al, al
    jz .done
    jmp .skip_simple
    
.skip_string:
    inc rsi                     ; Skip opening quote
.skip_str_loop:
    lodsb
    cmp al, '"'
    je .done
    cmp al, '\'
    jne .skip_str_loop
    lodsb                       ; Skip escaped char
    jmp .skip_str_loop
    
.done:
    ret

; Compare strings up to n characters or null
; rsi = string 1
; rdi = string 2
; Returns: carry flag set if equal
strcmp_n:
    push rax
    push rsi
    push rdi
    
.loop:
    mov al, [rsi]
    cmp al, [rdi]
    jne .not_equal
    
    test al, al
    jz .equal
    
    inc rsi
    inc rdi
    jmp .loop
    
.equal:
    stc                         ; Set carry = equal
    jmp .done
    
.not_equal:
    clc                         ; Clear carry = not equal
    
.done:
    pop rdi
    pop rsi
    pop rax
    ret

; Safe string copy with bounds checking
; rsi = source
; rdi = destination
strcpy_safe:
    push rax
    push rcx
    xor rcx, rcx
    
.loop:
    lodsb
    test al, al
    jz .done
    
    cmp rcx, MAX_NAME_LEN-1     ; Bounds check
    jae .done
    
    stosb
    inc rcx
    jmp .loop
    
.done:
    mov byte [rdi], 0           ; Ensure null termination
    pop rcx
    pop rax
    ret

; Include format_user_json from list_users
format_user_json:
    push rbp
    mov rbp, rsp
    push rdi
    
    APPEND_STRING '{"id":', rdi
    
    push rcx
    push r8
    mov eax, edx
    call int_to_str
    pop r8
    pop rcx
    
    APPEND_STRING ',"name":"', rdi
    
    push r8
    mov rsi, rcx
    call copy_string
    pop r8
    
    APPEND_STRING '","email":"', rdi
    
    mov rsi, r8
    call copy_string
    
    APPEND_STRING '"}', rdi
    
    pop rax
    sub rdi, rax
    mov rax, rdi
    
    pop rbp
    ret

; Copy string (from list_users)
copy_string:
.loop:
    lodsb
    test al, al
    jz .done
    stosb
    jmp .loop
.done:
    ret

; Integer to string conversion
int_to_str:
    push rbx
    push rdx
    push rcx
    
    mov ebx, 10
    xor rcx, rcx
    
.extract_digits:
    xor edx, edx
    div ebx
    push rdx
    inc rcx
    test eax, eax
    jnz .extract_digits
    
.write_digits:
    pop rax
    add al, '0'
    stosb
    loop .write_digits
    
    pop rcx
    pop rdx
    pop rbx
    ret