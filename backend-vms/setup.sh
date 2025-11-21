#!/bin/bash
set -e

VM_NAME=${VM_NAME:-backend}

echo "========================================="
echo "Backend VM: $VM_NAME"
echo "========================================="

# Create MOTD
cat > /etc/motd << EOF

========================================
Backend VM: $VM_NAME
========================================
You are connected to $VM_NAME via ContainerSSH routing!

EOF

# Start SSH daemon
echo "Starting SSH daemon..."
/usr/sbin/sshd -D -e
