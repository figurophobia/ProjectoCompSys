#!/bin/bash
# Simple Linux CPU monitor
# Prints a single line like: CPU: 12%

if command -v top >/dev/null 2>&1; then
    # Use top to get a quick snapshot
    cpu_line=$(top -bn1 | grep 'Cpu(s)' | head -n1)
    # Fallback parsing that works on many top implementations
    cpu_val=$(echo "$cpu_line" | awk -F',' '{print $1}' | awk '{print $2+0}')
    # If above parsing fails, use the earlier awk with field 8
    if [ -z "$cpu_val" ] || [[ "$cpu_val" == "0" ]]; then
        cpu_val=$(top -bn1 | grep 'Cpu(s)' | awk '{print 100-$8}' 2>/dev/null)
    fi
    if [ -z "$cpu_val" ]; then
        echo "CPU: Unknown"
    else
        # round
        cpu_int=$(printf "%.0f" "$cpu_val")
        echo "CPU: ${cpu_int}%"
    fi
else
    # Fallback to /proc/stat if top not available
    if [ -r /proc/stat ]; then
        # Read two samples for a short interval
        read -r cpu user nice system idle iowait irq softirq steal guest < /proc/stat
        total1=$((user+nice+system+idle+iowait+irq+softirq+steal))
        idle1=$idle
        sleep 0.2
        read -r cpu user nice system idle iowait irq softirq steal guest < /proc/stat
        total2=$((user+nice+system+idle+iowait+irq+softirq+steal))
        idle2=$idle
        total=$((total2-total1))
        idle_delta=$((idle2-idle1))
        if [ $total -gt 0 ]; then
            cpu_usage=$(( (100 * (total - idle_delta)) / total ))
            echo "CPU: ${cpu_usage}%"
        else
            echo "CPU: Unknown"
        fi
    else
        echo "CPU: Unknown"
    fi
fi
