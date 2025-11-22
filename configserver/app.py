#!/usr/bin/env python3
"""
ContainerSSH Config Server - SSH Routing Logic with OAuth
Routes users to different backend VMs based on username patterns
Extracts username from Google OAuth email and auto-provisions users
"""

import os
import json
import logging
import subprocess
import re
from flask import Flask, request, jsonify

app = Flask(__name__)
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

# Paths
DATA_DIR = "/data"
USERS_MAP_FILE = os.path.join(DATA_DIR, "users_map.json")
SERVICE_KEY = "/etc/containerssh/keys/backend_id_ed25519"
SERVICE_KEY_PUB = "/etc/containerssh/keys/backend_id_ed25519.pub"


def load_users_map():
    """Load user-to-backend mapping from JSON file"""
    if os.path.exists(USERS_MAP_FILE):
        try:
            with open(USERS_MAP_FILE, "r") as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Error loading users map: {e}")
    return {}


def extract_username_from_email(email):
    """
    Extract username from email address
    Examples:
      john.doe@gmail.com -> john.doe
      admin@company.com -> admin
      test+tag@example.com -> test+tag
    """
    if not email or "@" not in email:
        logger.warning(f"Invalid email format: {email}")
        return None

    username = email.split("@")[0]

    # Sanitize username for Unix compatibility
    # Replace any characters that aren't alphanumeric, dot, dash, or underscore
    username = re.sub(r"[^a-zA-Z0-9._-]", "_", username)

    # Ensure username doesn't start with a dash or dot
    username = re.sub(r"^[-.]", "_", username)

    # Truncate to 32 characters (Unix username limit)
    username = username[:32]

    logger.info(f"Extracted username '{username}' from email '{email}'")
    return username


def user_exists_on_vm(vm_hostname, username):
    """
    Check if user exists on the backend VM
    Returns True if user exists, False otherwise
    """
    try:
        # Use docker exec to check if user exists
        result = subprocess.run(
            ["docker", "exec", vm_hostname, "id", username],
            capture_output=True,
            text=True,
            timeout=5,
        )
        exists = result.returncode == 0
        logger.info(f"User '{username}' exists on {vm_hostname}: {exists}")
        return exists
    except Exception as e:
        logger.error(f"Error checking if user exists on {vm_hostname}: {e}")
        return False


def create_user_on_vm(vm_hostname, username):
    """
    Create a user account on the backend VM
    Sets up home directory, .ssh folder, and authorized_keys with backend service key
    """
    try:
        logger.info(f"Creating user '{username}' on {vm_hostname}")

        # 1. Create user account
        result = subprocess.run(
            [
                "docker",
                "exec",
                vm_hostname,
                "useradd",
                "-m",
                "-s",
                "/bin/bash",
                username,
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            logger.error(f"Failed to create user: {result.stderr}")
            return False

        # 2. Create .ssh directory
        subprocess.run(
            ["docker", "exec", vm_hostname, "mkdir", "-p", f"/home/{username}/.ssh"],
            capture_output=True,
            timeout=5,
        )

        # 3. Read backend service public key
        if not os.path.exists(SERVICE_KEY_PUB):
            logger.error(f"Backend service key not found: {SERVICE_KEY_PUB}")
            return False

        with open(SERVICE_KEY_PUB, "r") as f:
            service_key_pub = f.read().strip()

        # 4. Add service key to authorized_keys
        subprocess.run(
            [
                "docker",
                "exec",
                vm_hostname,
                "bash",
                "-c",
                f"echo '{service_key_pub}' > /home/{username}/.ssh/authorized_keys",
            ],
            capture_output=True,
            timeout=5,
        )

        # 5. Set correct permissions
        subprocess.run(
            [
                "docker",
                "exec",
                vm_hostname,
                "chown",
                "-R",
                f"{username}:{username}",
                f"/home/{username}/.ssh",
            ],
            capture_output=True,
            timeout=5,
        )

        subprocess.run(
            ["docker", "exec", vm_hostname, "chmod", "700", f"/home/{username}/.ssh"],
            capture_output=True,
            timeout=5,
        )

        subprocess.run(
            [
                "docker",
                "exec",
                vm_hostname,
                "chmod",
                "600",
                f"/home/{username}/.ssh/authorized_keys",
            ],
            capture_output=True,
            timeout=5,
        )

        logger.info(f"Successfully created user '{username}' on {vm_hostname}")
        return True

    except Exception as e:
        logger.error(f"Error creating user on {vm_hostname}: {e}")
        return False


def determine_target_backend(username, users_map):
    """
    Determine which backend VM to route user to
    Returns (vm_hostname, port)
    """
    # Check explicit mapping first
    if username in users_map:
        user_config = users_map[username]
        target_vm = user_config.get("backend", "backend_vm1")
        target_port = user_config.get("port", 22)
        logger.info(f"Explicit mapping: {username} -> {target_vm}:{target_port}")
        return target_vm, target_port

    # Pattern-based routing
    if username.startswith("admin") or username.startswith("ops"):
        target_vm = "backend_vm1"
    elif username.startswith("dev") or username.startswith("test"):
        target_vm = "backend_vm2"
    else:
        # Default routing
        target_vm = "backend_vm1"

    logger.info(f"Pattern-based routing: {username} -> {target_vm}:22")
    return target_vm, 22


@app.route("/config", methods=["POST"])
def config():
    """
    ContainerSSH configuration endpoint
    Extracts username from OAuth email, auto-provisions user, returns backend config
    """
    try:
        payload = request.get_json(force=True)

        # Log full payload for debugging
        logger.debug(
            f"Received config request payload: {json.dumps(payload, indent=2)}"
        )

        # Extract email from OAuth metadata
        # ContainerSSH passes OAuth claims in metadata field
        metadata = payload.get("metadata", {})
        email = metadata.get("oidc_email") or metadata.get("email")

        # Fallback: check if username is already an email
        provided_username = payload.get("username", "")
        if not email and "@" in provided_username:
            email = provided_username

        # if not email:
        #     logger.error("No email found in OAuth metadata")
        #     logger.error(f"Metadata received: {metadata}")
        #     return (
        #         jsonify(
        #             {"success": False, "error": "Email not found in OAuth metadata"}
        #         ),
        #         400,
        #     )

        # Extract username from email
        username = payload.get("username", "")

        # username = extract_username_from_email(email)
        if not username:
            logger.error(f"Failed to extract username from email: {email}")
            return jsonify({"success": False, "error": "Invalid email format"}), 400

        logger.info(
            f"Config request for email: {email}, extracted username: {username}"
        )

        # Load user mappings
        users_map = load_users_map()

        # Determine target backend
        target_vm, target_port = determine_target_backend(username, users_map)

        # # Check if user exists on target VM, create if not
        # if not user_exists_on_vm(target_vm, username):
        #     logger.info(f"User '{username}' does not exist on {target_vm}, creating...")
        #     if not create_user_on_vm(target_vm, username):
        #         return jsonify({
        #             "success": False,
        #             "error": f"Failed to create user on {target_vm}"
        #         }), 500
        # else:
        #     logger.info(f"User '{username}' already exists on {target_vm}")

        # Return SSH backend configuration
        config_response = {
            "config": {
                "backend": "sshproxy",
                "sshproxy": {
                    "server": target_vm,
                    "port": target_port,
                    "username": username,
                    "privateKey": SERVICE_KEY,
                    "allowedHostKeyFingerprints": [
                        "SHA256:kE5o9I4CYKDAA4O11TEC/z2rDdBxnuj5MXcdT8cF6GU"
                    ],
                },
            }
        }

        logger.info(f"Returning config for {username} -> {target_vm}:{target_port}")
        return jsonify(config_response), 200

    except Exception as e:
        logger.error(f"Error processing config request: {e}", exc_info=True)
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy"}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
