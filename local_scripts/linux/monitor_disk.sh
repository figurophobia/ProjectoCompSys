#!/bin/bash
# Simple Linux disk monitor for root (/)
# Prints a single line like: Size: 50G | Used: 20G | Free: 30G | Usage: 40%

if command -v df >/dev/null 2>&1; then
    line=$(df -h / | tail -n1)
    if [ -z "$line" ]; then
        echo "Disk: Unknown"
    else
        size=$(echo "$line" | awk '{print $2}')
        used=$(echo "$line" | awk '{print $3}')
        free=$(echo "$line" | awk '{print $4}')
        pct=$(echo "$line" | awk '{print $5}')
        echo "Size: ${size} | Used: ${used} | Free: ${free} | Usage: ${pct}"
    fi
else
    echo "Disk: Unknown"
fi
