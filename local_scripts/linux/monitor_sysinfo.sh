#!/bin/bash
# Simple Linux system info
# Prints Host, IP, Kernel and Uptime lines

echo "Host: $(hostname)"
ip=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "$ip" ]; then
    # fallback to ip route
    ip=$(ip -4 addr show scope global | awk '/inet/ {print $2}' | cut -d/ -f1 | head -n1)
fi
echo "IP: ${ip:-N/A}"
echo "Kernel: $(uname -r)"
upt=$(uptime -p 2>/dev/null || uptime)
echo "Uptime: ${upt}"
