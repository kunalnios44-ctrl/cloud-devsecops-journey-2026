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
if getent hosts github.com >/dev/null 2>&1; then
    getent hosts github.com
else
    echo "DNS resolution failed."
fi
echo

echo "HTTPS Connectivity:"
if curl -Is --max-time 10 https://github.com >/dev/null 2>&1; then
    echo "HTTPS connectivity: OK"
else
    echo "HTTPS connectivity: FAILED"
fi
echo

echo "Network diagnostics completed."
