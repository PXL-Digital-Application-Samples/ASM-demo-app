; Shared memory structures and constants
; This file contains all common definitions used across the CRUD API

%include "macros.inc"    ; Include our macro library

; Shared memory key
%define SHM_KEY 0x1234

; Shared memory size (64KB)
%define SHM_SIZE 65536

; Maximum name and email length
%define MAX_NAME_LEN 64
%define MAX_EMAIL_LEN 64

; User structure offsets
%define USER_SIZE 144
%define USER_ID 0           ; 4 bytes
%define USER_NEXT 8         ; 8 bytes (pointer)
%define USER_NAME 16        ; 64 bytes
%define USER_EMAIL 80       ; 64 bytes

; Shared memory header offsets
%define SHM_LOCK 0          ; 4 bytes (simple spinlock)
%define SHM_NEXT_ID 8       ; 4 bytes
%define SHM_HEAD 16         ; 8 bytes (pointer to first user)
%define SHM_FREE_SPACE 24   ; Start of free space for users

; System calls
%define SYS_READ 0
%define SYS_WRITE 1
%define SYS_OPEN 2
%define SYS_CLOSE 3
%define SYS_SHMGET 29
%define SYS_SHMAT 30
%define SYS_SHMDT 67
%define SYS_EXIT 60

; IPC flags
%define IPC_CREAT 0x200
%define IPC_EXCL 0x400

; JSON response buffer size
%define JSON_BUFFER_SIZE 4096