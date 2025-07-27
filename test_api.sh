#!/bin/bash

# Test script for x64 Assembly CRUD API

BASE_URL="http://localhost/api"

echo "========================================"
echo "x64 Assembly CRUD API - Test Suite"
echo "========================================"
echo

echo "1. Testing GET /api/users (List all users)"
echo "=========================================="
curl -s "$BASE_URL/users" | python3 -m json.tool || curl -s "$BASE_URL/users"
echo
echo

echo "2. Testing GET /api/users/1 (Get user 1)"
echo "=========================================="
curl -s "$BASE_URL/users/1" | python3 -m json.tool || curl -s "$BASE_URL/users/1"
echo
echo

echo "3. Testing GET /api/users/999 (Non-existent user)"
echo "=================================================="
curl -s "$BASE_URL/users/999" | python3 -m json.tool || curl -s "$BASE_URL/users/999"
echo
echo

echo "4. Testing POST /api/users (Create new user)"
echo "============================================"
curl -s -X POST -H "Content-Type: application/json" \
    -d '{"name":"Dave","email":"dave@example.com"}' \
    "$BASE_URL/users" | python3 -m json.tool || \
curl -s -X POST -H "Content-Type: application/json" \
    -d '{"name":"Dave","email":"dave@example.com"}' \
    "$BASE_URL/users"
echo
echo

echo "5. Testing GET /api/users (After create)"
echo "========================================"
curl -s "$BASE_URL/users" | python3 -m json.tool || curl -s "$BASE_URL/users"
echo
echo

echo "6. Testing PUT /api/users/1 (Update user 1)"
echo "==========================================="
curl -s -X PUT -H "Content-Type: application/json" \
    -d '{"name":"Alice Updated","email":"alice.updated@example.com"}' \
    "$BASE_URL/users/1" | python3 -m json.tool || \
curl -s -X PUT -H "Content-Type: application/json" \
    -d '{"name":"Alice Updated","email":"alice.updated@example.com"}' \
    "$BASE_URL/users/1"
echo
echo

echo "7. Testing GET /api/users/1 (After update)"
echo "=========================================="
curl -s "$BASE_URL/users/1" | python3 -m json.tool || curl -s "$BASE_URL/users/1"
echo
echo

echo "8. Testing PUT /api/users/2 (Partial update - name only)"
echo "========================================================"
curl -s -X PUT -H "Content-Type: application/json" \
    -d '{"name":"Bob Updated"}' \
    "$BASE_URL/users/2" | python3 -m json.tool || \
curl -s -X PUT -H "Content-Type: application/json" \
    -d '{"name":"Bob Updated"}' \
    "$BASE_URL/users/2"
echo
echo

echo "9. Testing DELETE /api/users/4 (Delete user 4)"
echo "=============================================="
curl -s -X DELETE "$BASE_URL/users/4" | python3 -m json.tool || curl -s -X DELETE "$BASE_URL/users/4"
echo
echo

echo "10. Testing GET /api/users (After delete)"
echo "========================================="
curl -s "$BASE_URL/users" | python3 -m json.tool || curl -s "$BASE_URL/users"
echo
echo

echo "11. Testing DELETE /api/users/4 (Delete already deleted user)"
echo "============================================================="
curl -s -X DELETE "$BASE_URL/users/4" | python3 -m json.tool || curl -s -X DELETE "$BASE_URL/users/4"
echo
echo

echo "12. Testing invalid JSON"
echo "========================"
curl -s -X POST -H "Content-Type: application/json" \
    -d '{"invalid json}' \
    "$BASE_URL/users" | python3 -m json.tool || \
curl -s -X POST -H "Content-Type: application/json" \
    -d '{"invalid json}' \
    "$BASE_URL/users"
echo
echo

echo "========================================"
echo "Test Suite Complete!"
echo "========================================"