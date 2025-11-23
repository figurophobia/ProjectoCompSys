#!/bin/bash
# Simple Linux memory monitor
# Prints a single line like: Total: 7.8G | Used: 3.1G | Free: 4.7G

if command -v free >/dev/null 2>&1; then
    # Use free -h for human readable output
    # We'll print the Mem line formatted
    mem_line=$(free -h | awk '/^Mem:/ {print $2" "$3" "$4}')
    if [ -z "$mem_line" ]; then
        echo "Memory: Unknown"
    else
        total=$(echo "$mem_line" | awk '{print $1}')
        used=$(echo "$mem_line" | awk '{print $2}')
        free_k=$(echo "$mem_line" | awk '{print $3}')
        echo "Total: ${total} | Used: ${used} | Free: ${free_k}"
    fi
else
    # Fallback using /proc/meminfo
    if [ -r /proc/meminfo ]; then
        total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        free_kb=$(awk '/MemFree/ {print $2}' /proc/meminfo)
        used_kb=$((total_kb - free_kb))
        # convert to GB with 2 decimals
        total_g=$(awk "BEGIN {printf \"%.2f\", $total_kb/1024/1024}")
        used_g=$(awk "BEGIN {printf \"%.2f\", $used_kb/1024/1024}")
        free_g=$(awk "BEGIN {printf \"%.2f\", $free_kb/1024/1024}")
        echo "Total: ${total_g}GB | Used: ${used_g}GB | Free: ${free_g}GB"
    else
        echo "Memory: Unknown"
    fi
fi
