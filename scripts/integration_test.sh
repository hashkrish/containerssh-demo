#!/usr/bin/env bash
#
# Integration tests for ContainerSSH environment
# Tests the full flow: SSH client -> ContainerSSH -> Config Server -> Backend VMs
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Allow specifying container suffix (e.g., "_test" for test containers)
CONTAINER_SUFFIX="${1:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

echo "========================================="
echo "ContainerSSH Integration Tests"
echo "========================================="
echo

# Helper function for test output
test_result() {
    local test_name="$1"
    local result="$2"

    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test 1: Config server health check
echo "Test 1: Config Server Health Check"
if curl -sf http://localhost:8080/health > /dev/null 2>&1; then
    test_result "Config server is healthy" 0
else
    test_result "Config server is healthy" 1
fi

# Test 2: Config server routing for admin user
echo "Test 2: Config Server Routing - Admin User"
RESPONSE=$(curl -sf -X POST http://localhost:8080/config \
    -H "Content-Type: application/json" \
    -d '{"username": "admin123"}' 2>/dev/null || echo "ERROR")

if echo "$RESPONSE" | grep -q '"server":"vm1"' 2>/dev/null; then
    test_result "Admin user routes to vm1" 0
else
    test_result "Admin user routes to vm1" 1
fi

# Test 3: Config server routing for dev user
echo "Test 3: Config Server Routing - Dev User"
RESPONSE=$(curl -sf -X POST http://localhost:8080/config \
    -H "Content-Type: application/json" \
    -d '{"username": "dev123"}' 2>/dev/null || echo "ERROR")

if echo "$RESPONSE" | grep -q '"server":"vm2"' 2>/dev/null; then
    test_result "Dev user routes to vm2" 0
else
    test_result "Dev user routes to vm2" 1
fi

# Test 4: SSH connection test for alice
echo "Test 4: SSH Connection - Alice Authentication"
if [ -f "$PROJECT_ROOT/data/test_keys/alice_id_ed25519" ]; then
    # Test if authentication works (connection may close due to backend issues)
    OUTPUT=$(timeout 10 ssh -i "$PROJECT_ROOT/data/test_keys/alice_id_ed25519" \
        -p 2222 \
        -o "StrictHostKeyChecking=no" \
        -o "UserKnownHostsFile=/dev/null" \
        -o "LogLevel=INFO" \
        -o "ConnectTimeout=5" \
        alice@localhost "echo test" 2>&1 || true)

    # Check if authentication succeeded (either command worked or got authenticated message)
    if echo "$OUTPUT" | grep -qE "(test|Authenticated to|Server accepts key)" || \
       timeout 5 ssh -i "$PROJECT_ROOT/data/test_keys/alice_id_ed25519" \
           -p 2222 \
           -o "StrictHostKeyChecking=no" \
           -o "UserKnownHostsFile=/dev/null" \
           -o "ConnectTimeout=5" \
           -o "BatchMode=yes" \
           alice@localhost exit 2>&1 | grep -q "Authenticated"; then
        test_result "Alice can authenticate via SSH" 0
    else
        test_result "Alice can authenticate via SSH" 1
    fi
else
    echo -e "${YELLOW}⊘${NC} Alice key not found, skipping SSH test"
fi

# Brief pause between SSH tests to avoid connection issues
sleep 2

# Test 5: SSH connection test for bob
echo "Test 5: SSH Connection - Bob Authentication"
if [ -f "$PROJECT_ROOT/data/test_keys/bob_id_ed25519" ]; then
    # Test if authentication works (connection may close due to backend issues)
    OUTPUT=$(timeout 10 ssh -i "$PROJECT_ROOT/data/test_keys/bob_id_ed25519" \
        -p 2222 \
        -o "StrictHostKeyChecking=no" \
        -o "UserKnownHostsFile=/dev/null" \
        -o "LogLevel=INFO" \
        -o "ConnectTimeout=5" \
        bob@localhost "echo test" 2>&1 || true)

    # Check if authentication succeeded
    if echo "$OUTPUT" | grep -qE "(test|Authenticated to|Server accepts key)" || \
       timeout 5 ssh -i "$PROJECT_ROOT/data/test_keys/bob_id_ed25519" \
           -p 2222 \
           -o "StrictHostKeyChecking=no" \
           -o "UserKnownHostsFile=/dev/null" \
           -o "ConnectTimeout=5" \
           -o "BatchMode=yes" \
           bob@localhost exit 2>&1 | grep -q "Authenticated"; then
        test_result "Bob can authenticate via SSH" 0
    else
        test_result "Bob can authenticate via SSH" 1
    fi
else
    echo -e "${YELLOW}⊘${NC} Bob key not found, skipping SSH test"
fi

# Test 6: Verify backend VM connectivity
echo "Test 6: Backend VM Connectivity"
VM1_STATUS=$(docker exec "backend_vm1${CONTAINER_SUFFIX}" echo "ok" 2>/dev/null || echo "ERROR")
VM2_STATUS=$(docker exec "backend_vm2${CONTAINER_SUFFIX}" echo "ok" 2>/dev/null || echo "ERROR")

if [ "$VM1_STATUS" = "ok" ] && [ "$VM2_STATUS" = "ok" ]; then
    test_result "Backend VMs are running" 0
else
    test_result "Backend VMs are running" 1
fi

# Test 7: SSH service running in backend VMs
echo "Test 7: Backend SSH Services"
VM1_SSH=$(docker exec "backend_vm1${CONTAINER_SUFFIX}" pgrep sshd > /dev/null 2>&1 && echo "ok" || echo "ERROR")
VM2_SSH=$(docker exec "backend_vm2${CONTAINER_SUFFIX}" pgrep sshd > /dev/null 2>&1 && echo "ok" || echo "ERROR")

if [ "$VM1_SSH" = "ok" ] && [ "$VM2_SSH" = "ok" ]; then
    test_result "SSH services running on backend VMs" 0
else
    test_result "SSH services running on backend VMs" 1
fi

# Test 8: Service key distribution
echo "Test 8: Service Key Distribution"
if [ -f "$PROJECT_ROOT/data/test_keys/alice_id_ed25519" ]; then
    ALICE_KEYS=$(docker exec "backend_vm1${CONTAINER_SUFFIX}" cat /home/alice/.ssh/authorized_keys 2>/dev/null || echo "ERROR")
    if [ "$ALICE_KEYS" != "ERROR" ] && [ -n "$ALICE_KEYS" ]; then
        test_result "Service keys distributed to backend VMs" 0
    else
        test_result "Service keys distributed to backend VMs" 1
    fi
else
    echo -e "${YELLOW}⊘${NC} Cannot verify key distribution without test keys"
fi

echo
echo "========================================="
echo "Test Summary"
echo "========================================="
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo "========================================="

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi

exit 0
