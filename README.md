# x64 Assembly CRUD API

A REST API implementation using pure x64 assembly language, nginx, and CGI. This project demonstrates low-level system programming with shared memory for state management.

## Features

- **Pure x64 Assembly**: All API logic implemented in NASM assembly
- **In-Memory Storage**: Uses System V shared memory for persistent state across CGI processes
- **Linked List Structure**: Simple linked list implementation in assembly
- **RESTful API**: Full CRUD operations (Create, Read, Update, Delete)
- **JSON Support**: Parses and generates JSON responses
- **Concurrent Access**: Simple spinlock for thread-safe operations
- **Docker**: Complete containerized environment

## Architecture

```
nginx (port 80)
  ↓
FastCGI
  ↓
CGI Programs (x64 Assembly)
  ↓
Shared Memory (SysV IPC)
```

### Components

1. **nginx**: Web server handling HTTP requests and routing to CGI
2. **fcgiwrap**: FastCGI wrapper for CGI programs
3. **Assembly CGI Programs**: Individual executables for each operation
4. **Shared Memory**: 64KB shared memory segment containing:
   - Spinlock for synchronization
   - Next ID counter
   - Linked list of users

## Quick Start

### Prerequisites

- Docker
- docker compose

### Running the API

```bash
# Build and start the container
docker compose up --build

# In another terminal, run tests
docker exec asm-crud-api /app/test_api.sh

# Or test individual endpoints
curl http://localhost:8080/api/users
```

### API Endpoints

- `GET /api/users` - List all users
- `GET /api/users/{id}` - Get specific user
- `POST /api/users` - Create new user
- `PUT /api/users/{id}` - Update user
- `DELETE /api/users/{id}` - Delete user

### Request/Response Examples

#### Create User
```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{"name":"John","email":"john@example.com"}' \
  http://localhost:8080/api/users
```

Response:
```json
{"id":4,"name":"John","email":"john@example.com"}
```

#### List Users
```bash
curl http://localhost:8080/api/users
```

Response:
```json
[
  {"id":1,"name":"Alice","email":"alice@example.com"},
  {"id":2,"name":"Bob","email":"bob@example.com"},
  {"id":3,"name":"Charlie","email":"charlie@example.com"}
]
```

## Implementation Details

### Memory Structure

```asm
; Shared memory layout
+0:   Lock (4 bytes)
+8:   Next ID (4 bytes)
+16:  Head pointer (8 bytes)
+24:  User data starts here

; User structure (144 bytes each)
+0:   ID (4 bytes)
+8:   Next pointer (8 bytes)
+16:  Name (64 bytes)
+80:  Email (64 bytes)
```

### Assembly Programs

- `init_shm.asm` - Initialize shared memory with seed data
- `list_users.asm` - GET /users implementation
- `get_user.asm` - GET /users/{id} implementation
- `create_user.asm` - POST /users implementation
- `update_user.asm` - PUT /users/{id} implementation
- `delete_user.asm` - DELETE /users/{id} implementation

### Key Techniques

1. **System Calls**: Direct Linux system calls for I/O, shared memory
2. **JSON Parsing**: Simple state machine for parsing JSON input
3. **String Formatting**: Manual sprintf-like implementation
4. **Environment Variables**: Reading CGI environment for parameters
5. **Spinlock**: Simple atomic exchange for mutual exclusion

## Building Without Docker

If you want to build on a Linux x64 system:

```bash
# Install dependencies
sudo apt-get install nasm nginx fcgiwrap

# Build assembly programs
make all

# Initialize shared memory
./cgi-bin/init_shm

# Configure nginx (see nginx.conf)
# Start nginx and fcgiwrap
```

## Debugging

### View Shared Memory

```bash
# Inside container
docker exec -it asm-crud-api bash

# List shared memory segments
ipcs -m

# Remove shared memory (if needed)
ipcrm -M 0x1234
```

### View Logs

```bash
# nginx logs
docker exec asm-crud-api cat /var/log/nginx/error.log
docker exec asm-crud-api cat /var/log/nginx/access.log
```
