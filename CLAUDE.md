# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a ContainerSSH demonstration environment focused on SSH session multiplexing and routing. ContainerSSH acts as an SSH gateway that authenticates users and routes their SSH sessions to different backend VMs based on username patterns or explicit mappings.

## Architecture

Three main components work together:

1. **ContainerSSH** (port 2222) - SSH gateway that intercepts client connections
2. **Config Server** (Flask, port 8080) - Provides routing logic and authentication via webhooks
3. **Backend VMs** (vm1, vm2) - Mock SSH servers representing infrastructure

**Request Flow:**
```
Client SSH → ContainerSSH → Config Server (routing decision) → Backend VM
```

## SSH Key Types

Three distinct SSH key types are used:

1. **Host Key** (`containerssh/keys/host_ed25519`) - ContainerSSH's identity to clients
2. **Backend Service Key** (`containerssh/keys/backend_id_ed25519`) - ContainerSSH authenticates to backends with this key; must be in authorized_keys on all backend VMs
3. **User Keys** (`data/test_keys/*_id_ed25519`) - Test users authenticate to ContainerSSH with these

## Common Commands

### Initial Setup
```bash
./scripts/generate_keys.sh    # Generate all SSH keys
./scripts/setup.sh             # Build images, start services, distribute keys
./scripts/verify.sh            # Verify setup works
```

### Daily Operations
```bash
# Start/stop services
docker-compose up -d
docker-compose down
docker-compose restart containerssh

# Test connections
./scripts/test_connection.sh alice
./scripts/test_connection.sh bob
ssh -i data/test_keys/alice_id_ed25519 -p 2222 alice@localhost

# View logs
docker-compose logs -f containerssh
docker-compose logs -f configserver
docker logs backend_vm1

# Debug config server
curl http://localhost:8080/health
curl -X POST http://localhost:8080/config -H "Content-Type: application/json" -d '{"username": "alice"}'

# Access backend VMs directly
docker exec -it backend_vm1 bash
docker exec -it containerssh sh
```

### Key Distribution (Production)
```bash
cd ansible

# Edit inventory.yml with real VM IPs, then:
ansible-playbook distribute_keys.yml
ansible backend_vms -m ping

# Rotate service keys (zero-downtime)
ansible-playbook rotate_keys.yml -e "new_key_path=../containerssh/keys/backend_id_ed25519.pub"
# After updating ContainerSSH and testing:
ansible-playbook rotate_keys.yml --tags remove_old -e "old_key_path=../containerssh/keys/backend_id_ed25519.pub.old"
```

## Routing Logic

The config server (`configserver/app.py`) implements routing in `/config` endpoint:

1. **Explicit mapping** - Checks `data/users_map.json` first
2. **Pattern-based routing** - Falls back to username prefix matching:
   - `admin*` or `ops*` → vm1
   - `dev*` or `test*` → vm2
   - Default → vm1

To modify routing:
- Edit `data/users_map.json` for explicit user-to-VM mappings
- Edit `configserver/app.py` lines 63-69 for pattern logic

## Authentication Flow

ContainerSSH uses webhooks for authentication (config v0.5):

1. **Public key auth** (`/pubkey` endpoint in `configserver/app.py`)
   - ContainerSSH sends username + public key to config server
   - Config server validates against authorized_keys in `data/users_map.json`
   - Returns success/failure

2. **Backend routing** (`/config` endpoint)
   - ContainerSSH requests backend config for authenticated user
   - Config server returns backend hostname, port, and service key path
   - ContainerSSH proxies connection using the backend service key

## Key Files

- `containerssh/config.yaml` - ContainerSSH configuration (v0.5 format)
- `configserver/app.py` - Routing logic and authentication webhooks
- `data/users_map.json` - User-to-backend mappings and authorized_keys
- `docker-compose.yml` - Full stack definition
- `backend-vms/setup.sh` - Backend VM initialization

## Adding New Users

```bash
# 1. Generate user key
ssh-keygen -t ed25519 -f data/test_keys/newuser_id_ed25519 -N ""

# 2. Add to data/users_map.json with backend mapping and public key

# 3. Create user on target backend VM
docker exec backend_vm1 useradd -m -s /bin/bash newuser
docker exec backend_vm1 mkdir -p /home/newuser/.ssh
docker exec backend_vm1 chown newuser:newuser /home/newuser/.ssh

# 4. Add backend service key to user's authorized_keys
BACKEND_KEY=$(cat containerssh/keys/backend_id_ed25519.pub)
docker exec backend_vm1 bash -c "echo '$BACKEND_KEY' > /home/newuser/.ssh/authorized_keys"
docker exec backend_vm1 chown newuser:newuser /home/newuser/.ssh/authorized_keys
docker exec backend_vm1 chmod 600 /home/newuser/.ssh/authorized_keys

# 5. Test
./scripts/test_connection.sh newuser
```

## Troubleshooting

**Connection refused on port 2222:**
- Check ContainerSSH is running: `docker ps | grep containerssh`
- Restart: `docker-compose restart containerssh`

**Permission denied (publickey):**
- Verify backend service key is distributed: `docker exec backend_vm1 cat /home/alice/.ssh/authorized_keys`
- Check config server logs: `docker-compose logs configserver`
- Test pubkey endpoint: `curl -X POST http://localhost:8080/pubkey -H "Content-Type: application/json" -d '{"username": "alice", "publicKey": "<key>"}'`

**Wrong backend routing:**
- Check config server logs for routing decision
- Verify `data/users_map.json` mappings
- Test config endpoint directly with curl

**Config server not responding:**
- Check health: `curl http://localhost:8080/health`
- View logs: `docker-compose logs configserver`
- Verify configserver container is running
