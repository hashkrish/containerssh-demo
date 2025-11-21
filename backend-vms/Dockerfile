FROM ubuntu:22.04

# Install OpenSSH server
RUN apt-get update && \
    apt-get install -y openssh-server sudo && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create run directory for SSH
RUN mkdir -p /run/sshd

# Configure SSH
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Create test users
RUN useradd -m -s /bin/bash alice && \
    useradd -m -s /bin/bash bob && \
    useradd -m -s /bin/bash admin-john && \
    useradd -m -s /bin/bash dev-sarah && \
    useradd -m -s /bin/bash testuser

# Create .ssh directories
RUN mkdir -p /home/alice/.ssh /home/bob/.ssh /home/admin-john/.ssh /home/dev-sarah/.ssh /home/testuser/.ssh && \
    chmod 700 /home/alice/.ssh /home/bob/.ssh /home/admin-john/.ssh /home/dev-sarah/.ssh /home/testuser/.ssh && \
    touch /home/alice/.ssh/authorized_keys && \
    touch /home/bob/.ssh/authorized_keys && \
    touch /home/admin-john/.ssh/authorized_keys && \
    touch /home/dev-sarah/.ssh/authorized_keys && \
    touch /home/testuser/.ssh/authorized_keys && \
    chmod 600 /home/alice/.ssh/authorized_keys && \
    chmod 600 /home/bob/.ssh/authorized_keys && \
    chmod 600 /home/admin-john/.ssh/authorized_keys && \
    chmod 600 /home/dev-sarah/.ssh/authorized_keys && \
    chmod 600 /home/testuser/.ssh/authorized_keys && \
    chown -R alice:alice /home/alice/.ssh && \
    chown -R bob:bob /home/bob/.ssh && \
    chown -R admin-john:admin-john /home/admin-john/.ssh && \
    chown -R dev-sarah:dev-sarah /home/dev-sarah/.ssh && \
    chown -R testuser:testuser /home/testuser/.ssh

# Copy setup script
COPY setup.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh

EXPOSE 22

CMD ["/usr/local/bin/setup.sh"]
