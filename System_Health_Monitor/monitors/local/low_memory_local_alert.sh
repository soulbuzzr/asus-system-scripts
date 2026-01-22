#!/bin/bash

# Get available memory in MB
AVAILABLE_MEM=$(free -wm | awk '/^Mem:/ { print $8 }')

# Set DISPLAY and DBUS_SESSION_BUS_ADDRESS for GUI access
export DISPLAY=:0
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

for i in {1..6}; do
    AVAILABLE_MEM=$(free -wm | awk '/^Mem:/ { print $8 }')
    # Check if available memory is below 1.5GB
    if [ "$AVAILABLE_MEM" -le 1536 ]; then
        notify-send "Warning: Low memory! Available: ${AVAILABLE_MEM}MB"
    fi

    sleep 10
done
