.PHONY: help setup keys env up up-build down restart logs logs-follow health test-ssh clean clean-all distribute-keys rotate-keys restart-configserver

# Default target
help:
	@echo "ContainerSSH Demo - Available Commands"
	@echo "======================================"
	@echo ""
	@echo "Initial Setup:"
	@echo "  make env              - Copy .env.example to .env (edit with OAuth credentials)"
	@echo "  make keys             - Generate SSH host and backend service keys"
	@echo "  make setup            - Full setup (build images, start services, distribute keys)"
	@echo ""
	@echo "Service Management:"
	@echo "  make up               - Start all services in background"
	@echo "  make down             - Stop all services"
	@echo "  make restart          - Restart ContainerSSH service"
	@echo "  make restart-all      - Restart all services"
	@echo ""
	@echo "Testing:"
	@echo "  make test-ssh         - Test SSH connection with OAuth flow"
	@echo "  make health           - Check config server health"
	@echo ""
	@echo "Logging & Debugging:"
	@echo "  make logs             - Show all service logs"
	@echo "  make logs-follow      - Follow all service logs (Ctrl+C to exit)"
	@echo "  make logs-ssh         - Show ContainerSSH logs"
	@echo "  make logs-config      - Show config server logs"
	@echo "  make logs-vm1         - Show backend VM1 logs"
	@echo "  make logs-vm2         - Show backend VM2 logs"
	@echo "  make shell-ssh        - Open shell in ContainerSSH container"
	@echo "  make shell-config     - Open shell in config server container"
	@echo "  make shell-vm1        - Open shell in backend VM1"
	@echo "  make shell-vm2        - Open shell in backend VM2"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean            - Stop services and remove containers"
	@echo "  make clean-all        - Stop services, remove containers and volumes"
	@echo ""
	@echo "Ansible (Production):"
	@echo "  make distribute-keys  - Distribute SSH keys to backend VMs"
	@echo "  make ping-backends    - Ping backend VMs via Ansible"

# Initial Setup
env:
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "Created .env file. Please edit it with your Google OAuth credentials."; \
	else \
		echo ".env file already exists."; \
	fi

keys:
	./scripts/generate_keys.sh

setup:
	./scripts/setup.sh

# Service Management
up:
	docker compose up -d

up-build:
	docker compose up -d --build --remove-orphans

down:
	docker compose down

restart:
	docker compose restart containerssh

restart-configserver:
	docker compose restart cs_configserver


restart-all:
	docker compose restart

# Testing
test-ssh:
	@echo "Connecting to ContainerSSH (username doesn't matter, will be extracted from email)..."
	@echo "Follow the OAuth prompts in your terminal."
	ssh anyuser@localhost -p 2222

health:
	@echo "Checking config server health..."
	@curl -s http://localhost:8080/health | python3 -m json.tool || echo "Config server not responding"

# Logging & Debugging
logs:
	docker compose logs --tail=100

logs-follow:
	docker compose logs -f

logs-ssh:
	docker compose logs -f containerssh

logs-config:
	docker compose logs -f configserver

logs-vm1:
	docker logs backend_vm1

logs-vm2:
	docker logs backend_vm2

shell-ssh:
	docker exec -it containerssh sh

shell-config:
	docker exec -it cs_configserver bash

shell-vm1:
	docker exec -it backend_vm1 bash

shell-vm2:
	docker exec -it backend_vm2 bash

# Cleanup
clean:
	docker compose down

clean-all:
	docker compose down -v
	@echo "All services stopped and volumes removed."

# Ansible Operations
distribute-keys:
	cd ansible && ansible-playbook distribute_keys.yml

ping-backends:
	cd ansible && ansible backend_vms -m ping

rotate-keys:
	@echo "Usage: make rotate-keys NEW_KEY_PATH=../containerssh/keys/backend_id_ed25519.pub"
	@if [ -z "$(NEW_KEY_PATH)" ]; then \
		echo "Error: NEW_KEY_PATH not specified"; \
		exit 1; \
	fi
	cd ansible && ansible-playbook rotate_keys.yml -e "new_key_path=$(NEW_KEY_PATH)"
