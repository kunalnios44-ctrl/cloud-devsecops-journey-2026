#!/bin/bash

echo "=== System Inventory Snapshot ==="
echo "Date: $(date)"
echo ""

# 1. Check Disk Usage (Using explicit file system types to block snap/overlay/tmpfs clutter)
echo "[+] Real Disk Partition Usage:"
if command -v df &> /dev/null; then
    df -h -t ext4 -t xfs -t btrfs -t vfat 2>/dev/null || df -h --local
else
    echo "Error: 'df' command not available."
fi
echo ""

# 2. Check Memory Usage (Human-readable GB/MB format)
echo "[+] Memory & Swap Usage:"
if command -v free &> /dev/null; then
    free -h
else
    echo "Error: 'free' command not available on this system."
fi
echo ""

# 3. Check System Uptime & Load Average (Fixed: removed -p so load average is fully visible)
echo "[+] System Uptime & Load Average:"
if command -v uptime &> /dev/null; then
    uptime
else
    echo "Error: 'uptime' command not available."
fi

echo ""
echo "=== Snapshot Complete (no automated health verdict) ==="
