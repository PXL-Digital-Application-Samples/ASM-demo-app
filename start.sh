#!/bin/bash

echo "Starting x64 Assembly CRUD API..."

# Initialize shared memory with seed data
echo "Initializing shared memory..."
/app/cgi-bin/init_shm

# Start fcgiwrap
echo "Starting fcgiwrap..."
/usr/sbin/fcgiwrap -s unix:/var/run/fcgiwrap.socket &
sleep 1

# Set permissions
chmod 666 /var/run/fcgiwrap.socket

# Start nginx
echo "Starting nginx..."
nginx -g "daemon off;"