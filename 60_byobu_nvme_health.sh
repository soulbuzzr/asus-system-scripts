#!/bin/bash

# NVMe0
nvme0=$(sudo nvme smart-log /dev/nvme0 2>/dev/null)
t0=$(echo "$nvme0" | grep -m1 "temperature" | awk '{print $3,$4}')
p0=$(echo "$nvme0" | grep "percentage_used" | awk '{print $3"%"}')
w0=$(echo "$nvme0" | grep "Data Units Written" | awk -F'[()]' '{print $2}' | awk '{print $1, $2}')

# NVMe1
nvme1=$(sudo nvme smart-log /dev/nvme1 2>/dev/null)
t1=$(echo "$nvme1" | grep -m1 "temperature" | awk '{print $3,$4}')
p1=$(echo "$nvme1" | grep "percentage_used" | awk '{print $3"%"}')
w1=$(echo "$nvme1" | grep "Data Units Written" | awk -F'[()]' '{print $2}' | awk '{print $1, $2}')

echo "NVMe0:$t0 | $p0 | W:$w0  ||  NVMe1:$t1 | $p1 | W:$w1"
