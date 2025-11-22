# Google OAuth Setup Guide

This guide walks you through setting up Google OAuth authentication for ContainerSSH.

## Overview

With Google OAuth enabled:
1. Users SSH to ContainerSSH (no SSH keys needed)
2. Terminal displays a Google OAuth URL and device code
3. User opens URL in browser and authenticates with Google
4. Username is extracted from their email (part before '@')
5. User account is automatically created on backend VM
6. SSH session establishes automatically

## Prerequisites

- Google Cloud account
- Docker and Docker Compose installed
- ContainerSSH demo environment

## Step 1: Create Google OAuth Credentials

### 1.1 Access Google Cloud Console
1. Go to https://console.cloud.google.com/
2. Sign in with your Google account

### 1.2 Create or Select Project
1. Click the project dropdown at the top
2. Click "New Project" or select an existing project
3. Give it a name like "ContainerSSH Demo"

### 1.3 Enable Required APIs
1. Go to "APIs & Services" > "Library"
2. Search for "Google+ API" or "Google Identity"
3. Click "Enable"

### 1.4 Create OAuth 2.0 Credentials
1. Go to "APIs & Services" > "Credentials"
2. Click "Create Credentials" > "OAuth 2.0 Client ID"
3. If prompted, configure the OAuth consent screen:
   - User Type: External (or Internal if using Google Workspace)
   - App name: ContainerSSH Demo
   - User support email: Your email
   - Scopes: Add `openid`, `email`, `profile`
   - Test users: Add your Google account email
4. Return to Credentials and create OAuth 2.0 Client ID:
   - Application type: **Web application**
   - Name: ContainerSSH
   - Authorized redirect URIs: (Leave empty - device flow doesn't need redirects)
5. Click "Create"
6. **Save the Client ID and Client Secret** - you'll need these

## Step 2: Configure ContainerSSH

### 2.1 Create Environment File
```bash
# Copy the example file
cp .env.example .env

# Edit with your credentials
nano .env
```

Add your Google OAuth credentials:
```bash
GOOGLE_CLIENT_ID=123456789-abcdefg.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-your-secret-here
```

### 2.2 Verify Configuration Files

The setup scripts have already configured:
- `containerssh/config.yaml` - OAuth2 device flow enabled
- `configserver/app.py` - Email extraction and user auto-provisioning
- `docker-compose.yml` - Environment variables and Docker socket access

## Step 3: Start the Environment

```bash
# Generate SSH keys (if not already done)
./scripts/generate_keys.sh

# Start all services
docker compose up -d

# Check logs
docker compose logs -f containerssh
docker compose logs -f configserver
```

## Step 4: Test OAuth Flow

### 4.1 Connect via SSH
```bash
ssh anyusername@localhost -p 2222
```

Note: The username you provide doesn't matter - it will be extracted from your Google email.

### 4.2 Complete OAuth in Browser
You should see output like:
```
To authenticate, visit: https://accounts.google.com/o/oauth2/device/code
Enter code: XXXX-XXXX
```

1. Open the URL in your browser
2. Enter the code shown in your terminal
3. Sign in with your Google account
4. Authorize the application

### 4.3 SSH Session Establishes
After successful authentication:
- Username is extracted from your email (e.g., `john.doe@gmail.com` → `john.doe`)
- User account is created on the appropriate backend VM
- SSH session connects automatically

## User Routing Logic

Users are routed to backend VMs based on username patterns:

- `admin*` or `ops*` → backend_vm1
- `dev*` or `test*` → backend_vm2
- All others → backend_vm1 (default)

You can customize routing in `configserver/app.py` (`determine_target_backend` function).

## Troubleshooting

### Issue: "Email not found in OAuth metadata"
**Cause:** OAuth scopes not properly configured

**Solution:**
1. Check `containerssh/config.yaml` has `email` scope
2. Verify Google OAuth consent screen includes email scope
3. Restart ContainerSSH: `docker compose restart containerssh`

### Issue: "Failed to create user on backend VM"
**Cause:** Config server can't access Docker socket

**Solution:**
1. Check Docker socket is mounted: `docker inspect cs_configserver | grep docker.sock`
2. Verify permissions: `ls -la /var/run/docker.sock`
3. Restart config server: `docker compose restart configserver`

### Issue: OAuth URL not appearing in terminal
**Cause:** OAuth not properly configured or keyboard-interactive not working

**Solution:**
1. Check ContainerSSH logs: `docker compose logs containerssh`
2. Verify environment variables are set: `docker exec containerssh env | grep GOOGLE`
3. Ensure SSH client supports keyboard-interactive (OpenSSH, PuTTY, etc.)
4. Try with verbose SSH: `ssh -v anyuser@localhost -p 2222`

### Issue: "Invalid client" error from Google
**Cause:** Client ID or Secret incorrect

**Solution:**
1. Verify credentials in `.env` file match Google Cloud Console
2. Ensure no extra spaces or quotes in `.env`
3. Restart ContainerSSH: `docker compose restart containerssh`

### Issue: User created but SSH connection fails
**Cause:** Backend service key not properly distributed

**Solution:**
1. Check service key exists: `ls -la containerssh/keys/backend_id_ed25519*`
2. Verify key in user's authorized_keys:
   ```bash
   docker exec backend_vm1 cat /home/username/.ssh/authorized_keys
   ```
3. Regenerate and distribute keys:
   ```bash
   ./scripts/generate_keys.sh
   ./scripts/setup.sh
   ```

## Advanced Configuration

### Custom Email Domain Restrictions

To restrict authentication to specific email domains, modify `configserver/app.py`:

```python
def extract_username_from_email(email):
    # Add domain validation
    if not email.endswith('@yourcompany.com'):
        logger.error(f"Email domain not allowed: {email}")
        return None

    username = email.split('@')[0]
    # ... rest of function
```

### Pre-provision Users Instead of Auto-creation

To disable auto-provisioning, comment out the user creation logic in `configserver/app.py`:

```python
# Check if user exists on target VM
if not user_exists_on_vm(target_vm, username):
    # Instead of creating, reject the connection
    return jsonify({
        "success": False,
        "error": f"User account not found on {target_vm}"
    }), 403
```

### Add OAuth Metadata to Logs

To log additional OAuth claims for debugging:

```python
# In configserver/app.py /config endpoint
logger.info(f"Full OAuth metadata: {json.dumps(metadata, indent=2)}")
```

## Security Considerations

1. **OAuth Consent Screen:** Use "Internal" user type if using Google Workspace to restrict to your organization
2. **Test Users:** In development, add test users to OAuth consent screen (required for unverified apps)
3. **Production:** Submit app for Google verification before production use
4. **Docker Socket:** Config server has Docker access for user provisioning - ensure it's secured
5. **Service Key:** Backend service key has access to all VMs - rotate regularly

## Reference

- ContainerSSH OAuth Documentation: https://containerssh.io/reference/auth/oauth2/
- Google OAuth Device Flow: https://developers.google.com/identity/protocols/oauth2/native-app
- OpenID Connect: https://openid.net/connect/
