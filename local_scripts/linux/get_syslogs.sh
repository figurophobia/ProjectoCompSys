#!/bin/bash
# get_syslogs.sh
# Retrieve recent system logs on Linux (journalctl preferred, fallback to /var/log)

MAX=${1:-100}

echo "=== Linux System Logs (last $MAX lines) ==="

if command -v journalctl >/dev/null 2>&1; then
    # Use journalctl for modern systems
    journalctl -n $MAX --no-pager
else
    # Try common syslog files
    if [ -f /var/log/syslog ]; then
        tail -n $MAX /var/log/syslog
    elif [ -f /var/log/messages ]; then
        tail -n $MAX /var/log/messages
    else
        echo "No system log (journalctl or /var/log/syslog /var/log/messages) available"
    fi
fi
