# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a ContainerSSH demonstration environment focused on SSH session multiplexing and routing with Google OAuth authentication. ContainerSSH acts as an SSH gateway that authenticates users via Google OAuth (device flow), extracts usernames from email addresses, auto-provisions user accounts, and routes SSH sessions to different backend VMs based on username patterns or explicit mappings.

## Architecture

Three main components work together:

1. **ContainerSSH** (port 2222) - SSH gateway that intercepts client connections
2. **Config Server** (Flask, port 8080) - Provides routing logic and authentication via webhooks
3. **Backend VMs** (vm1, vm2) - Mock SSH servers representing infrastructure

**Request Flow:**
```
Client SSH → ContainerSSH (OAuth device flow) → User authenticates in browser →
ContainerSSH extracts email → Config Server (extract username, auto-provision, routing) →
Backend VM
```

## SSH Key Types

Two SSH key types are used (OAuth replaces traditional user keys):

1. **Host Key** (`containerssh/keys/host_ed25519`) - ContainerSSH's identity to clients
2. **Backend Service Key** (`containerssh/keys/backend_id_ed25519`) - ContainerSSH authenticates to backends with this key; automatically added to authorized_keys during auto-provisioning

Note: User authentication is now handled via Google OAuth (device flow), not SSH keys.

## Common Commands

### Initial Setup
```bash
# 1. Set up Google OAuth credentials (see OAUTH_SETUP.md)
cp .env.example .env
# Edit .env with your Google OAuth Client ID and Secret

# 2. Generate SSH keys and start services
./scripts/generate_keys.sh    # Generate host and backend service keys
./scripts/setup.sh             # Build images, start services, distribute keys

# 3. Test OAuth flow
ssh anyuser@localhost -p 2222  # Username doesn't matter, will be extracted from email
# Follow OAuth prompts in terminal
```

### Daily Operations
```bash
# Start/stop services
docker compose up -d
docker compose down
docker compose restart containerssh

# Test OAuth connections (username doesn't matter, extracted from email)
ssh anyuser@localhost -p 2222
# Complete OAuth flow in browser when prompted

# View logs
docker compose logs -f containerssh
docker compose logs -f configserver
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

ContainerSSH uses Google OAuth2 with device flow (config v0.5):

1. **OAuth Device Flow** (keyboard-interactive authentication)
   - User initiates SSH connection
   - ContainerSSH displays OAuth URL and one-time code in terminal
   - User opens URL in browser and authenticates with Google
   - ContainerSSH polls Google until authentication completes
   - OAuth metadata (including email) is obtained

2. **User Provisioning & Routing** (`/config` endpoint in `configserver/app.py`)
   - ContainerSSH sends OAuth metadata (including `oidc_email`) to config server
   - Config server extracts username from email (part before '@')
   - Determines target backend VM using pattern-based routing or explicit mapping
   - Checks if user exists on target VM, auto-creates if not
   - Returns backend hostname, port, and service key path
   - ContainerSSH proxies connection using the backend service key

For detailed OAuth setup, see `OAUTH_SETUP.md`.

## Key Files

- `containerssh/config.yaml` - ContainerSSH configuration with OAuth2 device flow (v0.5 format)
- `configserver/app.py` - OAuth metadata handling, username extraction, user auto-provisioning, and routing logic
- `data/users_map.json` - Optional explicit user-to-backend mappings
- `docker-compose.yml` - Full stack definition with OAuth environment variables
- `.env` - Google OAuth credentials (Client ID and Secret) - create from `.env.example`
- `OAUTH_SETUP.md` - Detailed Google OAuth setup guide
- `backend-vms/setup.sh` - Backend VM initialization

## Adding New Users

With OAuth authentication, users are **automatically provisioned** on first login:

1. User authenticates via Google OAuth
2. Email is extracted (e.g., `john.doe@gmail.com`)
3. Username is extracted (e.g., `john.doe`)
4. Target backend VM is determined via routing logic
5. User account is automatically created on backend VM
6. Backend service key is added to `~/.ssh/authorized_keys`
7. SSH session establishes

**Manual Override (Optional):**
To explicitly map a user to a specific backend, add to `data/users_map.json`:
```json
{
  "john.doe": {
    "backend": "backend_vm2",
    "port": 22
  }
}
```

**Restricting Users:**
To restrict to specific email domains, modify `configserver/app.py` (`extract_username_from_email` function).

## Troubleshooting

**OAuth URL not appearing in terminal:**
- Check Google OAuth credentials: `docker exec containerssh env | grep GOOGLE`
- Verify `.env` file is loaded: `cat .env`
- Check ContainerSSH logs: `docker compose logs -f containerssh`
- Ensure SSH client supports keyboard-interactive (try: `ssh -v anyuser@localhost -p 2222`)

**"Email not found in OAuth metadata" error:**
- Verify OAuth scopes include `email` in `containerssh/config.yaml`
- Check ContainerSSH logs for OAuth response
- Ensure Google OAuth consent screen includes email scope

**"Failed to create user on backend VM" error:**
- Check config server can access Docker: `docker exec cs_configserver docker ps`
- Verify Docker socket is mounted: `docker inspect cs_configserver | grep docker.sock`
- Check backend VM is running: `docker ps | grep backend_vm`
- View config server logs: `docker compose logs -f configserver`

**Connection refused on port 2222:**
- Check ContainerSSH is running: `docker ps | grep containerssh`
- Restart: `docker compose restart containerssh`

**Wrong backend routing:**
- Check config server logs for routing decision
- Verify `data/users_map.json` mappings (if using explicit mapping)
- Review routing logic in `configserver/app.py` (`determine_target_backend` function)

**Config server not responding:**
- Check health: `curl http://localhost:8080/health`
- View logs: `docker compose logs configserver`
- Verify configserver container is running

**OAuth succeeds but SSH connection fails:**
- Check backend service key exists: `ls -la containerssh/keys/backend_id_ed25519*`
- Verify user was created: `docker exec backend_vm1 id <username>`
- Check authorized_keys: `docker exec backend_vm1 cat /home/<username>/.ssh/authorized_keys`
- Review backend VM logs: `docker logs backend_vm1`

For more detailed OAuth troubleshooting, see `OAUTH_SETUP.md`.
