#!/usr/bin/env bash
#
# Test SSH connection through ContainerSSH
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

USERNAME="${1:-alice}"
PORT="${2:-2222}"
HOST="${3:-localhost}"

KEY_FILE="$PROJECT_ROOT/data/test_keys/${USERNAME}_id_ed25519"

if [ ! -f "$KEY_FILE" ]; then
    echo "Error: Key file not found for user $USERNAME"
    echo "Expected: $KEY_FILE"
    echo
    echo "Available users:"
    ls -1 "$PROJECT_ROOT/data/test_keys/" | grep "_id_ed25519$" | sed 's/_id_ed25519$//' | sed 's/^/  - /'
    exit 1
fi

echo "========================================="
echo "Testing ContainerSSH Connection"
echo "========================================="
echo "User: $USERNAME"
echo "Host: $HOST"
echo "Port: $PORT"
echo "Key:  $KEY_FILE"
echo "========================================="
echo

# Test connection
ssh -i "$KEY_FILE" \
    -p "$PORT" \
    -o "StrictHostKeyChecking=no" \
    -o "UserKnownHostsFile=/dev/null" \
    -o "LogLevel=ERROR" \
    "${USERNAME}@${HOST}" \
    "hostname && echo 'Connected successfully!' && cat /etc/motd"

echo
echo "========================================="
echo "Connection test completed!"
echo "========================================="
