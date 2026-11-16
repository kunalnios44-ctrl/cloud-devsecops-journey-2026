
#!/usr/bin/env bash

set -u

echo "========================================"
echo "       Linux System Health Check"
echo "========================================"
echo

echo "System:"
uname -a
echo

echo "Uptime:"
uptime
echo

echo "Disk Usage:"
df -h
echo

echo "Memory Usage:"
if command -v free >/dev/null 2>&1; then
    free -h
else
    echo "Memory information is not available on this system."
fi
echo

echo "Running Processes:"
if command -v ps >/dev/null 2>&1; then
    ps aux | head -n 10
else
    echo "Process information is not available on this system."
fi
echo

echo "Network:"
if command -v ip >/dev/null 2>&1; then
    ip addr show
else
    echo "IP command is not available on this system."
fi

echo
echo "Health check completed successfully."
