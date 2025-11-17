#!/bin/bash
# Update script - executed as root
echo "Starting system update on $(hostname)..."

if command -v apt &> /dev/null; then
    echo "Using APT package manager..."
    apt update
    apt autoremove -y

echo "Update completed successfully on $(hostname)"