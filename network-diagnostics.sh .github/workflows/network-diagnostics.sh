
#!/usr/bin/env bash

echo "========================================"
echo "       Network Diagnostics"
echo "========================================"
echo

echo "Hostname:"
hostname
echo

echo "IP Address:"
if command -v ip >/dev/null 2>&1; then
    ip addr show
else
    echo "ip command is not available."
fi
echo

echo "Routing Table:"
if command -v ip >/dev/null 2>&1; then
    ip route
else
    echo "ip command is not available."
fi
echo

echo "DNS Resolution:"
if command -v getent >/dev/null 2>&1; then
    if getent hosts github.com; then
        echo "DNS Resolution: OK"
    else
        echo "DNS Resolution: FAILED"
    fi
else
    echo "getent command is not available."
fi
echo

echo "HTTPS Connectivity:"
if command -v curl >/dev/null 2>&1; then
    if curl -sS -o /dev/null --max-time 10 \
        -w "HTTP Status: %{http_code}\n" \
        https://github.com; then
        echo "HTTPS Connectivity: OK"
    else
        echo "HTTPS Connectivity: FAILED"
    fi
else
    echo "curl command is not available."
fi
echo

echo "Network diagnostics completed successfully."
