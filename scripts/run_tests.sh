#!/usr/bin/env bash
#
# Run tests in Docker containers
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TEST_TYPE="${1:-all}"

cd "$PROJECT_ROOT"

echo "========================================="
echo "Running Tests in Docker Containers"
echo "========================================="
echo

# Function to run unit tests
run_unit_tests() {
    echo -e "${BLUE}Running unit tests...${NC}"
    echo

    # Build and run unit tests
    docker compose -f docker-compose.test.yml build configserver-test

    if docker compose -f docker-compose.test.yml run --rm configserver-test; then
        echo
        echo -e "${GREEN}✓ Unit tests passed${NC}"
        return 0
    else
        echo
        echo -e "${RED}✗ Unit tests failed${NC}"
        return 1
    fi
}

# Function to run integration tests
run_integration_tests() {
    echo -e "${BLUE}Running integration tests...${NC}"
    echo

    # Ensure keys are generated
    if [ ! -f "$PROJECT_ROOT/data/test_keys/alice_id_ed25519" ]; then
        echo "Generating SSH keys..."
        "$SCRIPT_DIR/generate_keys.sh"
    fi

    # Ensure keys are readable by containers
    chmod 644 "$PROJECT_ROOT/containerssh/keys/host_ed25519" 2>/dev/null || true
    chmod 644 "$PROJECT_ROOT/containerssh/keys/backend_id_ed25519" 2>/dev/null || true

    # Start services for integration testing
    echo "Starting services..."
    docker compose -f docker-compose.test.yml up -d configserver containerssh vm1 vm2

    # Wait for services to be ready
    echo "Waiting for services to start..."
    sleep 10

    # Check if services are healthy
    echo "Checking service health..."
    if ! curl -sf http://localhost:8080/health > /dev/null 2>&1; then
        echo -e "${RED}Config server is not responding${NC}"
        docker compose -f docker-compose.test.yml logs configserver
        docker compose -f docker-compose.test.yml down -v
        return 1
    fi

    # Distribute keys to backend VMs (using test container suffix)
    echo "Distributing keys to backend VMs..."
    "$SCRIPT_DIR/distribute_keys.sh" "_test" || true

    # Run integration tests (pass container suffix for test containers)
    echo "Running integration test suite..."
    if "$SCRIPT_DIR/integration_test.sh" "_test"; then
        echo
        echo -e "${GREEN}✓ Integration tests passed${NC}"
        RESULT=0
    else
        echo
        echo -e "${RED}✗ Integration tests failed${NC}"
        echo
        echo "Showing logs for debugging:"
        echo -e "${YELLOW}=== ContainerSSH logs ===${NC}"
        docker compose -f docker-compose.test.yml logs --tail=50 containerssh
        echo
        echo -e "${YELLOW}=== Config Server logs ===${NC}"
        docker compose -f docker-compose.test.yml logs --tail=50 configserver
        RESULT=1
    fi

    # Cleanup
    echo
    echo "Cleaning up test environment..."
    docker compose -f docker-compose.test.yml down -v

    return $RESULT
}

# Main execution
UNIT_RESULT=0
INTEGRATION_RESULT=0

case "$TEST_TYPE" in
    unit)
        run_unit_tests
        UNIT_RESULT=$?
        ;;
    integration)
        run_integration_tests
        INTEGRATION_RESULT=$?
        ;;
    all)
        run_unit_tests
        UNIT_RESULT=$?
        echo
        echo "========================================="
        echo
        run_integration_tests
        INTEGRATION_RESULT=$?
        ;;
    *)
        echo "Usage: $0 [unit|integration|all]"
        echo "  unit         - Run only unit tests"
        echo "  integration  - Run only integration tests"
        echo "  all          - Run all tests (default)"
        exit 1
        ;;
esac

echo
echo "========================================="
echo "Test Results Summary"
echo "========================================="

if [ "$TEST_TYPE" = "unit" ] || [ "$TEST_TYPE" = "all" ]; then
    if [ $UNIT_RESULT -eq 0 ]; then
        echo -e "Unit tests:        ${GREEN}PASSED${NC}"
    else
        echo -e "Unit tests:        ${RED}FAILED${NC}"
    fi
fi

if [ "$TEST_TYPE" = "integration" ] || [ "$TEST_TYPE" = "all" ]; then
    if [ $INTEGRATION_RESULT -eq 0 ]; then
        echo -e "Integration tests: ${GREEN}PASSED${NC}"
    else
        echo -e "Integration tests: ${RED}FAILED${NC}"
    fi
fi

echo "========================================="

# Exit with error if any tests failed
if [ $UNIT_RESULT -ne 0 ] || [ $INTEGRATION_RESULT -ne 0 ]; then
    exit 1
fi

exit 0
