#!/usr/bin/env bash
#
# Distribute backend service key to backend VMs
# Can be used with different docker-compose configurations
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Allow specifying VM suffix (for test containers)
VM_SUFFIX="${1:-}"

cd "$PROJECT_ROOT"

echo "Distributing backend service key to VMs..."

BACKEND_KEY_PUB=$(cat "$PROJECT_ROOT/containerssh/keys/backend_id_ed25519.pub")

for vm in vm1 vm2; do
    CONTAINER_NAME="backend_${vm}${VM_SUFFIX}"
    echo "  → Configuring $CONTAINER_NAME..."

    # Check if container exists and is running
    if ! docker exec "$CONTAINER_NAME" echo "Container accessible" > /dev/null 2>&1; then
        echo "    ⚠ Container $CONTAINER_NAME not accessible, skipping..."
        continue
    fi

    for user in alice bob admin-john dev-sarah testuser; do
        docker exec "$CONTAINER_NAME" bash -c "echo '$BACKEND_KEY_PUB' >> /home/$user/.ssh/authorized_keys" 2>/dev/null || true
    done
done

echo "Done!"
