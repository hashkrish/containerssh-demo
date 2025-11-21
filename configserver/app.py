#!/usr/bin/env python3
"""
ContainerSSH Config Server - SSH Routing Logic
Routes users to different backend VMs based on username patterns
"""

import os
import json
import logging
from flask import Flask, request, jsonify

app = Flask(__name__)
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

# Paths
DATA_DIR = "/data"
USERS_MAP_FILE = os.path.join(DATA_DIR, "users_map.json")
SERVICE_KEY = "/etc/containerssh/keys/backend_id_ed25519"

def load_users_map():
    """Load user-to-backend mapping from JSON file"""
    if os.path.exists(USERS_MAP_FILE):
        try:
            with open(USERS_MAP_FILE, "r") as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Error loading users map: {e}")
    return {}


@app.route("/config", methods=["POST"])
def config():
    """
    ContainerSSH configuration endpoint
    Returns backend configuration based on username
    """
    try:
        payload = request.get_json(force=True)
        username = payload.get("username", "")

        if not username:
            logger.warning("Request missing username")
            return jsonify({"success": False}), 400

        logger.info(f"Config request for user: {username}")

        # Load user mappings
        users_map = load_users_map()

        # Determine target backend
        target_vm = None
        target_port = 22

        # Check explicit mapping first
        if username in users_map:
            user_config = users_map[username]
            target_vm = user_config.get("backend", "vm1")
            target_port = user_config.get("port", 22)
            logger.info(f"Explicit mapping: {username} -> {target_vm}:{target_port}")
        else:
            # Pattern-based routing
            if username.startswith("admin") or username.startswith("ops"):
                target_vm = "vm1"
            elif username.startswith("dev") or username.startswith("test"):
                target_vm = "vm2"
            else:
                # Default routing
                target_vm = "vm1"

            logger.info(f"Pattern-based routing: {username} -> {target_vm}:{target_port}")

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
                    ]
                }
            }
        }

        return jsonify(config_response), 200

    except Exception as e:
        logger.error(f"Error processing config request: {e}")
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/pubkey", methods=["POST"])
def pubkey():
    """
    Public key authentication endpoint
    Validates user public keys
    """
    try:
        payload = request.get_json(force=True)
        username = payload.get("username", "")
        public_key = payload.get("publicKey", "")

        logger.info(f"Pubkey auth request for user: {username}")
        logger.info(f"Received public key length: {len(public_key)}, first 80 chars: {public_key[:80]}")

        # Load authorized keys for user
        users_map = load_users_map()

        if username in users_map:
            authorized_keys = users_map[username].get("authorized_keys", [])
            logger.info(f"User {username} has {len(authorized_keys)} authorized keys")

            # Simple key matching (in production, use proper SSH key comparison)
            for authorized_key in authorized_keys:
                logger.info(f"Authorized key length: {len(authorized_key)}, first 80 chars: {authorized_key[:80]}")
                # Check if the key data matches (strip whitespace and comments)
                if authorized_key.strip() in public_key.strip() or public_key.strip() in authorized_key.strip():
                    logger.info(f"Public key accepted for {username}")
                    return jsonify({"success": True}), 200

        logger.warning(f"Public key rejected for {username}")
        return jsonify({"success": False}), 403

    except Exception as e:
        logger.error(f"Error processing pubkey request: {e}")
        return jsonify({"success": False}), 500


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy"}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
