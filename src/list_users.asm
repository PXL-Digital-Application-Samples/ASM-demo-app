; CGI script to list all users
; Returns JSON array of all users from shared memory
; 
; Memory layout visualization:
; Shared Memory: [Lock|NextID|Head] -> User1 -> User2 -> User3 -> NULL
; JSON Output: [{"id":1,...},{"id":2,...},{"id":3,...}]

%include "shared.inc"

section .data
    ; HTTP response header for JSON content
    content_type db "Content-Type: application/json", 10, 10, 0
    
    ; JSON structure components
    json_start db "[", 0
    json_end db "]", 10, 0
    json_comma db ",", 0

section .bss
    ; Temporary buffer for formatting individual user JSON
    user_json resb 256

section .text
global _start

_start:
    ; === Send HTTP headers ===
    HTTP_JSON_HEADER
    
    ; === Connect to shared memory ===
    ; Get shared memory ID using our predefined key
    mov rax, SYS_SHMGET
    mov rdi, SHM_KEY
    mov rsi, SHM_SIZE
    mov rdx, 0666o
    syscall
    
    test rax, rax
    js .error_exit          ; Jump if shmget failed (negative return)
    mov r12, rax            ; r12 = shared memory ID
    
    ; Attach shared memory to our address space
    mov rax, SYS_SHMAT
    mov rdi, r12
    xor rsi, rsi
    xor rdx, rdx
    syscall
    
    test rax, rax
    js .error_exit          ; Jump if shmat failed
    mov r13, rax            ; r13 = shared memory base address
    
    ; === Acquire exclusive access ===
    ACQUIRE_LOCK r13, SHM_LOCK
    
    ; === Start JSON array ===
    SYSCALL WRITE, 1, json_start, 1
    
    ; === Traverse linked list of users ===
    mov r14, [r13 + SHM_HEAD]   ; r14 = current user pointer
    xor r15, r15                ; r15 = first_user flag (0 = first)
    
.traverse_users:
    test r14, r14               ; Check if current user is NULL
    jz .done                    ; Exit loop if no more users
    
    ; Add comma separator (except before first user)
    test r15, r15
    jz .skip_comma
    SYSCALL WRITE, 1, json_comma, 1
    
.skip_comma:
    mov r15, 1                  ; Set flag: no longer first user
    
    ; === Format current user as JSON ===
    mov rdi, user_json          ; Output buffer
    mov edx, [r14 + USER_ID]    ; User ID
    lea rcx, [r14 + USER_NAME]  ; User name pointer
    lea r8, [r14 + USER_EMAIL]  ; User email pointer
    call format_user_json
    
    ; Write formatted JSON to stdout
    SYSCALL WRITE, 1, user_json, rax  ; rax contains length from format_user_json
    
    ; Move to next user in linked list
    mov r14, [r14 + USER_NEXT]
    jmp .traverse_users
    
.done:
    ; === Cleanup and exit ===
    RELEASE_LOCK r13, SHM_LOCK
    
    ; End JSON array
    SYSCALL WRITE, 1, json_end, 2
    
    ; Detach from shared memory
    SYSCALL SHMDT, r13
    
    ; Exit successfully
    SYSCALL EXIT, 0

.error_exit:
    ; Write error response
    JSON_ERROR "Failed to access shared memory"
    SYSCALL EXIT, 1

; ===================================================================
; format_user_json - Format a user structure as JSON string
; Input:
;   rdi = output buffer
;   edx = user ID
;   rcx = pointer to name string
;   r8  = pointer to email string
; Output:
;   rax = length of formatted string
; ===================================================================
format_user_json:
    push rbp
    mov rbp, rsp
    push rdi                    ; Save start of buffer
    
    ; Build JSON: {"id":
    APPEND_STRING '{"id":', rdi
    
    ; Convert ID to string
    push rcx                    ; Save name pointer
    push r8                     ; Save email pointer
    mov eax, edx
    call int_to_str             ; Convert ID in eax to string at rdi
    pop r8
    pop rcx
    
    ; Add: ,"name":"
    APPEND_STRING ',"name":"', rdi
    
    ; Copy name string
    push r8                     ; Save email pointer
    mov rsi, rcx
    call copy_string            ; Copy from rsi to rdi
    pop r8
    
    ; Add: ","email":"
    APPEND_STRING '","email":"', rdi
    
    ; Copy email string
    mov rsi, r8
    call copy_string
    
    ; Close JSON: "}
    APPEND_STRING '"}', rdi
    
    ; Calculate total length
    pop rax                     ; Get original buffer start
    sub rdi, rax                ; Length = current - start
    mov rax, rdi
    
    pop rbp
    ret

; ===================================================================
; copy_string - Copy null-terminated string
; Input:
;   rsi = source string
;   rdi = destination buffer
; Output:
;   rdi = updated to point after copied string
; ===================================================================
copy_string:
.loop:
    lodsb                       ; Load byte from [rsi] to al, increment rsi
    test al, al                 ; Check for null terminator
    jz .done
    stosb                       ; Store al to [rdi], increment rdi
    jmp .loop
.done:
    ret

; ===================================================================
; int_to_str - Convert integer to decimal string
; Input:
;   eax = integer to convert
;   rdi = output buffer
; Output:
;   rdi = updated to point after number
; ===================================================================
int_to_str:
    push rbx
    push rdx
    push rcx
    
    mov ebx, 10                 ; Divisor for decimal conversion
    xor rcx, rcx                ; Digit counter
    
    ; Extract digits in reverse order
.extract_digits:
    xor edx, edx                ; Clear for division
    div ebx                     ; eax/10, remainder in edx
    push rdx                    ; Save digit
    inc rcx                     ; Count digit
    test eax, eax               ; More digits?
    jnz .extract_digits
    
    ; Write digits in correct order
.write_digits:
    pop rax                     ; Get digit
    add al, '0'                 ; Convert to ASCII
    stosb                       ; Write to buffer
    loop .write_digits
    
    pop rcx
    pop rdx
    pop rbx
    ret