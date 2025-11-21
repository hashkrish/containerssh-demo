# ContainerSSH Demo - Quick Reference

## One-Time Setup

```bash
./scripts/generate_keys.sh    # Generate all SSH keys
./scripts/setup.sh             # Build & start everything
./scripts/verify.sh            # Verify setup works
```

## Daily Commands

```bash
# Start/Stop
docker-compose up -d           # Start all services
docker-compose down            # Stop all services
docker-compose restart         # Restart services

# Test Connections
./scripts/test_connection.sh alice      # Test as alice
./scripts/test_connection.sh bob        # Test as bob
ssh -i data/test_keys/alice_id_ed25519 -p 2222 alice@localhost

# View Logs
docker-compose logs -f containerssh     # ContainerSSH logs
docker-compose logs -f configserver     # Config server logs
docker logs backend_vm1                 # Backend VM logs

# Debugging
curl http://localhost:8080/health       # Config server health
docker exec -it containerssh sh         # ContainerSSH shell
docker exec -it backend_vm1 bash        # Backend VM shell
```

## File Locations

| Item | Path |
|------|------|
| User routing config | `data/users_map.json` |
| ContainerSSH config | `containerssh/config.yaml` |
| Routing logic | `configserver/app.py` |
| Backend service key | `containerssh/keys/backend_id_ed25519` |
| Test user keys | `data/test_keys/` |

## User Routing

**Current mappings:**
- `alice` → vm1
- `bob` → vm2
- `admin-*` → vm1 (pattern)
- `dev-*` → vm2 (pattern)
- Others → vm1 (default)

Edit `data/users_map.json` and `configserver/app.py` to change.

## Ansible (Production)

```bash
cd ansible

# Distribute service key to real VMs
ansible-playbook distribute_keys.yml

# Rotate keys (zero-downtime)
ansible-playbook rotate_keys.yml

# Check backend VM status
ansible backend_vms -m ping
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Port 2222 refused | `docker-compose restart containerssh` |
| Publickey denied | Check `./scripts/verify.sh` output |
| Config server down | `docker-compose logs configserver` |
| Wrong VM routing | Check `data/users_map.json` and config server logs |

## Architecture at a Glance

```
User → ContainerSSH:2222 → Config Server → Routes to Backend VM
         (auth with          (routing          (auth with
          user key)           logic)            service key)
```

## Next Steps

1. Read full documentation: `README.md`
2. Customize routing: `configserver/app.py`
3. Add users: Edit `data/users_map.json`
4. Production hardening: See README security checklist
