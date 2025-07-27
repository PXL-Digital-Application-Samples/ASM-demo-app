#!/bin/bash

# Cleanup script for shared memory

echo "Cleaning up shared memory..."

# Find and remove shared memory with key 0x1234
SHMID=$(ipcs -m | grep "0x00001234" | awk '{print $2}')

if [ -n "$SHMID" ]; then
    echo "Found shared memory segment: $SHMID"
    ipcrm -m $SHMID
    echo "Shared memory removed."
else
    echo "No shared memory segment found with key 0x1234"
fi

echo "Cleanup complete."