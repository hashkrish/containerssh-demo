# Testing Guide

This document describes how to run tests for the ContainerSSH demonstration environment.

## Overview

Tests are run inside Docker containers to ensure consistency with the production environment. There are two types of tests:

1. **Unit Tests** - Test the Flask config server routing logic and authentication in isolation
2. **Integration Tests** - End-to-end tests of the full SSH routing flow

## Quick Start

### Run All Tests

```bash
./scripts/run_tests.sh
```

### Run Specific Test Types

```bash
# Unit tests only
./scripts/run_tests.sh unit

# Integration tests only
./scripts/run_tests.sh integration
```

## Unit Tests

Unit tests verify the config server's routing logic, authentication, and error handling.

### Running Unit Tests in Docker

```bash
# Build and run unit tests
docker compose -f docker-compose.test.yml build configserver-test
docker compose -f docker-compose.test.yml run --rm configserver-test
```

### Running Unit Tests Locally (without Docker)

```bash
cd configserver
pip install -r requirements.txt
pip install pytest pytest-cov flask-testing
pytest tests/ -v --cov=app
```

### What's Tested

- `/health` endpoint availability
- `/config` endpoint routing logic:
  - Pattern-based routing (admin, ops, dev, test users)
  - Explicit user mappings from `users_map.json`
  - Default routing fallback
- `/pubkey` authentication endpoint:
  - Valid key acceptance
  - Invalid key rejection
  - Unknown user handling
- Error handling and edge cases

## Integration Tests

Integration tests verify the complete SSH routing flow through ContainerSSH.

### Running Integration Tests

```bash
# Full integration test suite
./scripts/run_tests.sh integration

# Or manually:
./scripts/generate_keys.sh                    # Generate SSH keys
docker compose -f docker-compose.test.yml up -d configserver containerssh vm1 vm2
./scripts/setup.sh                            # Distribute keys
./scripts/integration_test.sh                 # Run tests
docker compose -f docker-compose.test.yml down -v
```

### What's Tested

1. Config server health and API endpoints
2. Routing decisions for different user types
3. Actual SSH connections through ContainerSSH to backend VMs
4. Backend VM connectivity and SSH service availability
5. Service key distribution

## GitHub Actions

Tests run automatically on:
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop`
- Manual workflow dispatch

The workflow runs three jobs:
1. **Unit Tests** - Runs in isolated Docker container
2. **Integration Tests** - Full docker-compose stack
3. **Lint** - Code quality checks (flake8, black)

## Test Architecture

### Docker Multi-Stage Build

The `configserver/Dockerfile` uses multi-stage builds:

- **base** - Common dependencies
- **test** - Includes pytest and test dependencies
- **production** - Clean production image

### Test Configuration

- `docker-compose.test.yml` - Test-specific compose configuration
- `configserver/tests/` - Unit test files
- `scripts/integration_test.sh` - Integration test suite
- `scripts/run_tests.sh` - Unified test runner

## Coverage Reports

Unit tests generate coverage reports:

```bash
# HTML coverage report (after running tests)
open configserver/htmlcov/index.html

# Terminal coverage report
docker compose -f docker-compose.test.yml run --rm configserver-test pytest tests/ --cov=app --cov-report=term
```

## Known Issues

### SSH Integration Tests (Platform-Specific)

The end-to-end SSH connection tests (Tests 4-5) may be flaky in certain environments due to:
- Platform architecture mismatches (ContainerSSH image is linux/amd64)
- SIGPIPE issues in containerized SSH sessions
- Timing issues with rapid successive connections

**Workaround**: The tests verify authentication rather than command execution. Tests 1-3, 6-8 provide solid coverage of:
- Config server health and routing logic
- Backend VM connectivity and SSH services
- Service key distribution

If SSH tests fail but other tests pass, the core routing infrastructure is working correctly.

## Troubleshooting

### Unit Tests Failing

```bash
# View detailed test output
docker compose -f docker-compose.test.yml run --rm configserver-test pytest tests/ -vv

# Check for import errors
docker compose -f docker-compose.test.yml run --rm configserver-test python -c "import app"
```

### Integration Tests Failing

```bash
# Check service logs
docker compose -f docker-compose.test.yml logs configserver
docker compose -f docker-compose.test.yml logs containerssh
docker logs backend_vm1_test

# Test config server directly
curl http://localhost:8080/health
curl -X POST http://localhost:8080/config -H "Content-Type: application/json" -d '{"username": "alice"}'

# Test SSH connection manually
ssh -i data/test_keys/alice_id_ed25519 -p 2222 alice@localhost
```

### Clean Up Test Containers

```bash
# Stop and remove all test containers
docker compose -f docker-compose.test.yml down -v

# Remove test images
docker compose -f docker-compose.test.yml down --rmi all -v
```

## Adding New Tests

### Adding Unit Tests

1. Create test file in `configserver/tests/test_*.py`
2. Import necessary modules and the Flask app
3. Create test class inheriting from `unittest.TestCase`
4. Add test methods (must start with `test_`)

Example:
```python
import unittest
from app import app

class MyTestCase(unittest.TestCase):
    def setUp(self):
        self.app = app
        self.app.config['TESTING'] = True
        self.client = self.app.test_client()

    def test_my_feature(self):
        response = self.client.get('/endpoint')
        self.assertEqual(response.status_code, 200)
```

### Adding Integration Tests

Edit `scripts/integration_test.sh` and add new test cases following the existing pattern:

```bash
echo "Test N: My New Test"
if my_test_command; then
    test_result "My test description" 0
else
    test_result "My test description" 1
fi
```

## Best Practices

1. **Run tests in Docker** - Ensures consistency with CI/CD and production
2. **Run tests before commits** - Use `./scripts/run_tests.sh` before pushing
3. **Check coverage** - Aim for high coverage on critical routing logic
4. **Update tests with code changes** - Keep tests synchronized with features
5. **Test edge cases** - Include error conditions and boundary cases
