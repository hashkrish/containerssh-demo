#!/usr/bin/env bash
#
# Generate SSH keys for ContainerSSH demo
# - ContainerSSH host key (what clients see)
# - Backend service key (ContainerSSH uses to auth to backend VMs)
# - Test user keys (for testing connections)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

KEYS_DIR="$PROJECT_ROOT/containerssh/keys"
TEST_KEYS_DIR="$PROJECT_ROOT/data/test_keys"

echo "========================================="
echo "ContainerSSH Key Generation"
echo "========================================="
echo

# Create directories
mkdir -p "$KEYS_DIR"
mkdir -p "$TEST_KEYS_DIR"
chmod 700 "$KEYS_DIR"
chmod 700 "$TEST_KEYS_DIR"

# 1. Generate ContainerSSH host key
echo "[1/3] Generating ContainerSSH host key..."
if [ -f "$KEYS_DIR/host_ed25519" ]; then
    echo "  → Host key already exists, skipping"
else
    ssh-keygen -t ed25519 -f "$KEYS_DIR/host_ed25519" -N "" -C "containerssh-host-key"
    chmod 600 "$KEYS_DIR/host_ed25519"
    chmod 644 "$KEYS_DIR/host_ed25519.pub"
    echo "  ✓ Host key generated"
fi

# 2. Generate backend service key (ContainerSSH uses this to auth to backend VMs)
echo "[2/3] Generating backend service key..."
if [ -f "$KEYS_DIR/backend_id_ed25519" ]; then
    echo "  → Backend service key already exists, skipping"
else
    ssh-keygen -t ed25519 -f "$KEYS_DIR/backend_id_ed25519" -N "" -C "containerssh-backend-service-key"
    chmod 600 "$KEYS_DIR/backend_id_ed25519"
    chmod 644 "$KEYS_DIR/backend_id_ed25519.pub"
    echo "  ✓ Backend service key generated"
fi

# 3. Generate test user keys
echo "[3/3] Generating test user keys..."
for user in alice bob admin-john dev-sarah testuser; do
    if [ -f "$TEST_KEYS_DIR/${user}_id_ed25519" ]; then
        echo "  → Key for $user already exists, skipping"
    else
        ssh-keygen -t ed25519 -f "$TEST_KEYS_DIR/${user}_id_ed25519" -N "" -C "test-user-${user}"
        chmod 600 "$TEST_KEYS_DIR/${user}_id_ed25519"
        chmod 644 "$TEST_KEYS_DIR/${user}_id_ed25519.pub"
        echo "  ✓ Key for $user generated"
    fi
done

echo
echo "========================================="
echo "Keys generated successfully!"
echo "========================================="
echo
echo "Next steps:"
echo "  1. Run: ./scripts/setup.sh"
echo "  2. Or manually distribute backend service key:"
echo "     - Public key: $KEYS_DIR/backend_id_ed25519.pub"
echo "     - Must be added to authorized_keys on backend VMs"
echo
