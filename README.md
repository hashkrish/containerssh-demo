# ContainerSSH Demo - SSH Multiplexing & Routing

A complete local exploration environment for ContainerSSH focused on **SSH session multiplexing and routing**. This setup demonstrates how ContainerSSH acts as an SSH gateway, routing users to different backend VMs based on username patterns or explicit mappings.

## Architecture

```
┌─────────┐
│ Client  │
│ (SSH)   │
└────┬────┘
     │
     │ SSH (port 2222)
     │
┌────▼──────────────┐
│  ContainerSSH     │  ◄─── Queries config for routing decisions
│  (Gateway)        │
└────┬──────────────┘
     │
     ├──────────────┐
     │              │
┌────▼────┐    ┌───▼─────┐
│  VM1    │    │  VM2    │
│ Backend │    │ Backend │
└─────────┘    └─────────┘
```

### Components

1. **ContainerSSH** - SSH gateway that authenticates users and routes sessions
2. **Config Server** - Flask app that provides routing logic per user
3. **Backend VMs** - Mock SSH servers (vm1, vm2) representing real infrastructure

### Routing Logic

The config server implements flexible routing:

- **Explicit mapping**: User-to-VM mapping in `data/users_map.json`
- **Pattern-based routing**:
  - Users starting with `admin` or `ops` → vm1
  - Users starting with `dev` or `test` → vm2
  - Default → vm1

## Quick Start

### Prerequisites

- Docker & Docker Compose
- SSH client
- (Optional) Ansible for production key distribution

### Setup (3 minutes)

```bash
# 1. Generate all SSH keys
./scripts/generate_keys.sh

# 2. Build and start everything
./scripts/setup.sh

# 3. Verify setup
./scripts/verify.sh
```

### Test Connection

```bash
# Test as alice (routes to vm1)
./scripts/test_connection.sh alice

# Test as bob (routes to vm2)
./scripts/test_connection.sh bob

# Test as dev-sarah (routes to vm2 via pattern)
./scripts/test_connection.sh dev-sarah
```

Or manually:

```bash
ssh -i data/test_keys/alice_id_ed25519 -p 2222 alice@localhost
```

## Project Structure

```
.
├── docker-compose.yml           # Full stack definition
├── containerssh/
│   ├── config.yaml             # ContainerSSH configuration
│   └── keys/                   # SSH keys (generated)
├── configserver/
│   ├── app.py                  # Routing logic (Flask)
│   ├── Dockerfile
│   └── requirements.txt
├── backend-vms/
│   ├── Dockerfile              # Mock SSH backend
│   └── setup.sh
├── data/
│   ├── users_map.json          # User routing configuration
│   ├── known_hosts             # Backend host keys (generated)
│   └── test_keys/              # Test user keys (generated)
├── scripts/
│   ├── generate_keys.sh        # Generate all SSH keys
│   ├── setup.sh                # Full setup automation
│   ├── verify.sh               # Verify everything works
│   └── test_connection.sh      # Test SSH connection
└── ansible/
    ├── distribute_keys.yml     # Deploy keys to backends
    ├── rotate_keys.yml         # Zero-downtime key rotation
    ├── inventory.yml           # Backend VM inventory
    └── ansible.cfg
```

## Key Management

### SSH Keys Explained

This setup uses **three types of SSH keys**:

1. **ContainerSSH Host Key** (`containerssh/keys/host_ed25519`)
   - What clients see when connecting to ContainerSSH
   - Similar to server host key in normal SSH

2. **Backend Service Key** (`containerssh/keys/backend_id_ed25519`)
   - ContainerSSH uses this to authenticate to backend VMs
   - Public key must be in `authorized_keys` on all backend VMs
   - This is the key you rotate in production

3. **User Keys** (`data/test_keys/<user>_id_ed25519`)
   - Individual user keys for testing
   - Users authenticate to ContainerSSH with these
   - In production, users provide their own public keys

### Key Distribution (Production)

For real backend VMs, use Ansible to distribute the backend service key:

```bash
cd ansible

# Edit inventory.yml with your real VM IPs
# Then distribute the service key:
ansible-playbook distribute_keys.yml

# Verify:
ansible backend_vms -m shell -a "tail -n 1 /home/alice/.ssh/authorized_keys"
```

### Key Rotation (Zero-Downtime)

Rotate the backend service key without interrupting service:

```bash
# 1. Generate new key
ssh-keygen -t ed25519 -f containerssh/keys/backend_id_ed25519.new -N ""

# 2. Add new key to all backends (keeps old key working)
cd ansible
ansible-playbook rotate_keys.yml \
  -e "new_key_path=../containerssh/keys/backend_id_ed25519.new.pub"

# 3. Update ContainerSSH to use new key
cp containerssh/keys/backend_id_ed25519 containerssh/keys/backend_id_ed25519.old
cp containerssh/keys/backend_id_ed25519.new containerssh/keys/backend_id_ed25519
docker restart containerssh

# 4. Test connections work
./scripts/test_connection.sh alice

# 5. Remove old key from backends
ansible-playbook rotate_keys.yml --tags remove_old \
  -e "old_key_path=../containerssh/keys/backend_id_ed25519.old.pub"
```

## Configuration

### User Routing

Edit `data/users_map.json`:

```json
{
  "alice": {
    "backend": "vm1",
    "port": 22,
    "authorized_keys": []
  },
  "bob": {
    "backend": "vm2",
    "port": 22,
    "authorized_keys": []
  }
}
```

### Routing Logic

Customize routing in `configserver/app.py`:

```python
# Pattern-based routing
if username.startswith("admin"):
    target_vm = "vm1"
elif username.startswith("dev"):
    target_vm = "vm2"
```

## Troubleshooting

### View Logs

```bash
# ContainerSSH logs
docker compose logs -f containerssh

# Config server logs
docker compose logs -f configserver

# Backend VM logs
docker logs backend_vm1
docker logs backend_vm2
```

### Common Issues

**Connection refused on port 2222**
```bash
# Check ContainerSSH is running
docker ps | grep containerssh

# Check port binding
docker port containerssh
```

**Permission denied (publickey)**
```bash
# Verify service key is on backend
docker exec backend_vm1 cat /home/alice/.ssh/authorized_keys

# Should contain: containerssh/keys/backend_id_ed25519.pub
```

**Config server not responding**
```bash
# Test config server health
curl http://localhost:8080/health

# Check config server logs
docker logs cs_configserver
```

### Manual Testing

Test individual components:

```bash
# Test config server directly
curl -X POST http://localhost:8080/config \
  -H "Content-Type: application/json" \
  -d '{"username": "alice"}'

# Test backend VM directly
docker exec -it backend_vm1 bash
# Inside: cat /etc/motd

# Test service key auth to backend
ssh -i containerssh/keys/backend_id_ed25519 alice@localhost -p <vm_port>
```

## Production Hardening

Before deploying to production:

### Security Checklist

- [ ] Use real VMs, not Docker containers for backends
- [ ] Run ContainerSSH as systemd service, not Docker
- [ ] Store keys in secrets manager (Vault, AWS Secrets Manager)
- [ ] Enable firewall rules limiting SSH access
- [ ] Use fail2ban for rate limiting
- [ ] Enable audit logging and ship to SIEM
- [ ] Set up monitoring & alerts
- [ ] Use strong host key algorithms only
- [ ] Disable root login on backends
- [ ] Implement RBAC via config server
- [ ] Use mTLS between ContainerSSH and config server
- [ ] Regular key rotation schedule (90 days)

### Recommended Changes

**containerssh/config.yaml** - Add strict crypto:
```yaml
ssh:
  kex:
    - curve25519-sha256
  ciphers:
    - aes256-gcm@openssh.com
  macs:
    - hmac-sha2-256-etm@openssh.com
  hostKeyAlgorithms:
    - ssh-ed25519
```

**Config server** - Add authentication:
```python
@app.before_request
def check_auth():
    token = request.headers.get('Authorization')
    if token != os.getenv('CONFIG_SERVER_TOKEN'):
        abort(401)
```

**Ansible** - Use vault for sensitive data:
```bash
ansible-vault encrypt containerssh/keys/backend_id_ed25519
```

## Advanced Usage

### Add New User

```bash
# 1. Generate user key
ssh-keygen -t ed25519 -f data/test_keys/newuser_id_ed25519 -N ""

# 2. Add user to routing config
# Edit data/users_map.json

# 3. Create user on target backend
docker exec backend_vm1 useradd -m -s /bin/bash newuser
docker exec backend_vm1 mkdir -p /home/newuser/.ssh
docker exec backend_vm1 chown newuser:newuser /home/newuser/.ssh

# 4. Add service key to new user's authorized_keys
docker exec backend_vm1 bash -c \
  "cat /home/alice/.ssh/authorized_keys > /home/newuser/.ssh/authorized_keys"
docker exec backend_vm1 chown newuser:newuser /home/newuser/.ssh/authorized_keys

# 5. Test
ssh -i data/test_keys/newuser_id_ed25519 -p 2222 newuser@localhost
```

### Add New Backend VM

```bash
# 1. Add to docker-compose.yml
# 2. Add to configserver routing logic
# 3. Run setup to distribute service key
# 4. Add to ansible/inventory.yml for production
```

### Custom Authentication

Modify `configserver/app.py` `pubkey()` endpoint to integrate with:
- LDAP/Active Directory
- Database of authorized keys
- External auth service (OAuth, SAML)

## Performance & Scaling

- Config server is stateless → scale horizontally
- Use Redis/Memcached for user mapping cache
- ContainerSSH supports connection pooling to backends
- Monitor with Prometheus exporter (available in ContainerSSH)

## Further Reading

- [ContainerSSH Documentation](https://containerssh.io/)
- [ContainerSSH Config Server API](https://containerssh.io/reference/api/)
- [SSH Key Management Best Practices](https://www.ssh.com/academy/ssh/public-key-authentication)

## License

MIT

## Contributing

This is a demo/exploration environment. For production deployments, review and adapt to your security requirements.
