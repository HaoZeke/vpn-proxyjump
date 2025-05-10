FROM alpine:latest

LABEL maintainer="rgoswami[at]ieee[dot]org"
LABEL description="Alpine jumphost: OpenConnect (interactive) as main process, OpenSSH server for ProxyJump."

ARG SSH_USER_NAME=jumphostuser
# It's safer to pass the public key content at build time than to have a default here that might be forgotten.
ARG USER_PUBLIC_KEY

# Install necessary packages
RUN apk add --no-cache \
    tini \
    openconnect \
    openssh-server \
    bash \
    ca-certificates

# Create a non-root user for SSH connections INTO the container
RUN adduser -D -s /bin/bash "${SSH_USER_NAME}"

# Setup SSH for this user using the public key provided at build time
RUN mkdir -p "/home/${SSH_USER_NAME}/.ssh" && \
    chmod 700 "/home/${SSH_USER_NAME}/.ssh" && \
    echo "${USER_PUBLIC_KEY}" > "/home/${SSH_USER_NAME}/.ssh/authorized_keys" && \
    chmod 600 "/home/${SSH_USER_NAME}/.ssh/authorized_keys" && \
    chown -R "${SSH_USER_NAME}:${SSH_USER_NAME}" "/home/${SSH_USER_NAME}/.ssh"

# Configure SSHD for security and ProxyJump functionality
RUN sed -i 's/^#?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/^#?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/^#?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config && \
    echo "AllowAgentForwarding yes" >> /etc/ssh/sshd_config && \
    echo "GatewayPorts no" >> /etc/ssh/sshd_config && \
    echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config && \
    echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config

# Generate SSH host keys if they don't exist
RUN ssh-keygen -A

# Expose the SSH port
EXPOSE 22

# Use tini to manage the main process.
# The CMD will be a shell script that starts sshd and then execs openconnect.
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["sh", "-c", "\
set -e; \
echo 'Starting SSH daemon...'; \
/usr/sbin/sshd -e; \
sleep 2; \
echo 'SSH daemon active. Starting OpenConnect interactively...'; \
echo 'You will be prompted for your EPFL VPN password.'; \
exec openconnect vpn.epfl.ch \
    -u goswami@epfl.ch \
    --useragent='AnyConnect' \
    --script=/etc/vpnc/vpnc-script \
"]
