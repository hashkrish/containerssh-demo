#!/usr/bin/env bash
#
# Setup script for ContainerSSH demo
# Prepares all necessary files and distributes keys
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "========================================="
echo "ContainerSSH Demo - Setup"
echo "========================================="
echo

# Step 1: Generate keys
echo "[Step 1/4] Generating SSH keys..."
bash "$SCRIPT_DIR/generate_keys.sh"

# Step 2: Build Docker images
echo
echo "[Step 2/4] Building Docker images..."
docker-compose build

# Step 3: Start services
echo
echo "[Step 3/4] Starting services..."
docker-compose up -d

# Wait for services to be ready
echo
echo "Waiting for services to start..."
sleep 5

# Step 4: Distribute backend service key to VMs
echo
echo "[Step 4/4] Distributing backend service key to VMs..."

BACKEND_KEY_PUB=$(cat "$PROJECT_ROOT/containerssh/keys/backend_id_ed25519.pub")

for vm in vm1 vm2; do
    echo "  → Configuring $vm..."
    for user in alice bob admin-john dev-sarah testuser; do
        docker exec "backend_$vm" bash -c "echo '$BACKEND_KEY_PUB' >> /home/$user/.ssh/authorized_keys"
    done
done

# Generate known_hosts file
echo
echo "Generating known_hosts file..."
rm -f "$PROJECT_ROOT/data/known_hosts"
for vm in vm1 vm2; do
    docker exec "backend_$vm" cat /etc/ssh/ssh_host_ed25519_key.pub | \
        awk "{print \"$vm \" \$0}" >> "$PROJECT_ROOT/data/known_hosts"
done

echo
echo "========================================="
echo "Setup complete!"
echo "========================================="
echo
echo "Test the setup with:"
echo "  ./scripts/test_connection.sh alice"
echo "  ./scripts/test_connection.sh bob"
echo
echo "Or manually:"
echo "  ssh -i data/test_keys/alice_id_ed25519 -p 2222 alice@localhost"
echo
echo "View logs:"
echo "  docker-compose logs -f containerssh"
echo "  docker-compose logs -f configserver"
echo
