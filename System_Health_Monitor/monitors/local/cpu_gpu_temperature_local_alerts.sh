#!/bin/bash

# Set DISPLAY and DBUS for GUI notifications
export DISPLAY=:0
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

# Thresholds
CPU_LIMIT=75
GPU_LIMIT=80

for i in {1..6}; do
    # Get CPU temperature (Tctl from k10temp)
    CPU_TEMP=$(sensors | awk '/Tctl:/ {gsub("\\+",""); print $2}' | sed 's/°C//')

    # Get GPU temperature (edge from amdgpu)
    GPU_TEMP=$(sensors | awk '/edge:/ {gsub("\\+",""); print $2}' | sed 's/°C//')

    # Get NVIDIA GPU temperature
    if command -v nvidia-smi >/dev/null 2>&1; then
        NVIDIA_GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu \
            --format=csv,noheader,nounits 2>/dev/null)
    fi

    # Check CPU temperature
    if [ -n "$CPU_TEMP" ] && [ "$(echo "$CPU_TEMP > $CPU_LIMIT" | bc -l)" -eq 1 ]; then
        notify-send "⚠️ Warning: High CPU Temp" "Current: ${CPU_TEMP}°C (Limit: ${CPU_LIMIT}°C)"
    fi

    # Check GPU temperature
    if [ -n "$GPU_TEMP" ] && [ "$(echo "$GPU_TEMP > $GPU_LIMIT" | bc -l)" -eq 1 ]; then
        notify-send "⚠️ Warning: High GPU Temp" "Current: ${GPU_TEMP}°C (Limit: ${GPU_LIMIT}°C)"
    fi

    # Check NVIDIA GPU temperature
    if [ -n "$NVIDIA_GPU_TEMP" ] && \
       [ "$(echo "$NVIDIA_GPU_TEMP > $GPU_LIMIT" | bc -l)" -eq 1 ]; then
        notify-send "⚠️ Warning: High GPU Temp (NVIDIA)" \
            "Current: ${NVIDIA_GPU_TEMP}°C (Limit: ${GPU_LIMIT}°C)"
    fi

    sleep 10
done
