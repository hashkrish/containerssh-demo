#!/usr/bin/env bash
#
# Verification script for ContainerSSH setup
# Checks all components are working correctly
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "========================================="
echo "ContainerSSH Setup Verification"
echo "========================================="
echo

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

FAILED=0

# Check 1: Docker containers running
echo "Checking Docker containers..."
for container in containerssh cs_configserver backend_vm1 backend_vm2; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        check_pass "Container $container is running"
    else
        check_fail "Container $container is NOT running"
        FAILED=$((FAILED + 1))
    fi
done
echo

# Check 2: SSH keys exist
echo "Checking SSH keys..."
if [ -f "containerssh/keys/host_ed25519" ]; then
    check_pass "ContainerSSH host key exists"
else
    check_fail "ContainerSSH host key missing"
    FAILED=$((FAILED + 1))
fi

if [ -f "containerssh/keys/backend_id_ed25519" ]; then
    check_pass "Backend service key exists"
else
    check_fail "Backend service key missing"
    FAILED=$((FAILED + 1))
fi
echo

# Check 3: Config server responding
echo "Checking config server..."
if curl -s http://localhost:8080/health | grep -q "healthy"; then
    check_pass "Config server is healthy"
else
    check_fail "Config server not responding"
    FAILED=$((FAILED + 1))
fi
echo

# Check 4: ContainerSSH port listening
echo "Checking ContainerSSH SSH port..."
if nc -z localhost 2222 2>/dev/null; then
    check_pass "ContainerSSH listening on port 2222"
else
    check_fail "ContainerSSH not listening on port 2222"
    FAILED=$((FAILED + 1))
fi
echo

# Check 5: Backend VMs accessible
echo "Checking backend VMs..."
for vm in vm1 vm2; do
    if docker exec "backend_${vm}" pgrep sshd >/dev/null; then
        check_pass "Backend $vm SSH daemon running"
    else
        check_fail "Backend $vm SSH daemon NOT running"
        FAILED=$((FAILED + 1))
    fi
done
echo

# Check 6: Test user keys exist
echo "Checking test user keys..."
for user in alice bob admin-john dev-sarah testuser; do
    if [ -f "data/test_keys/${user}_id_ed25519" ]; then
        check_pass "Test key for $user exists"
    else
        check_warn "Test key for $user missing"
    fi
done
echo

# Check 7: Service key distributed to backends
echo "Checking service key distribution..."
BACKEND_KEY=$(cat containerssh/keys/backend_id_ed25519.pub)
for vm in vm1 vm2; do
    if docker exec "backend_${vm}" grep -q "$BACKEND_KEY" /home/alice/.ssh/authorized_keys 2>/dev/null; then
        check_pass "Service key deployed to $vm"
    else
        check_fail "Service key NOT found on $vm"
        FAILED=$((FAILED + 1))
    fi
done
echo

# Summary
echo "========================================="
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    echo
    echo "Try testing a connection:"
    echo "  ./scripts/test_connection.sh alice"
    echo
else
    echo -e "${RED}$FAILED check(s) failed${NC}"
    echo
    echo "Fix issues and run setup again:"
    echo "  ./scripts/setup.sh"
    echo
    exit 1
fi
echo "========================================="
