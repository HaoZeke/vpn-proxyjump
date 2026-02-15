FROM alpine:latest

LABEL maintainer="rgoswami[at]ieee[dot]org"
LABEL description="Alpine jumphost: OpenConnect/OpenFortiVPN + OpenSSH server for ProxyJump."
LABEL org.opencontainers.image.source="https://github.com/HaoZeke/vpn-proxyjump"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.licenses="MIT"

ARG SSH_USER_NAME=jumphostuser
ARG USER_PUBLIC_KEY

# Add edge/testing repo for openfortivpn
RUN { \
    echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing"; \
} >> /etc/apk/repositories && \
apk update

# Install necessary packages
RUN apk add --no-cache \
    tini \
    openconnect \
    openfortivpn \
    ppp \
    iptables \
    ppp-pppoe \
    openssh \
    openssh-server \
    openssh-server-pam \
    vpnc \
    socat \
    mosh \
    bash \
    ca-certificates

# Create a non-root user for SSH connections, then lock the account.
# Public key authentication is the only way in.
RUN adduser -g "${SSH_USER_NAME}" -D -s /bin/bash "${SSH_USER_NAME}" && \
    passwd -l "${SSH_USER_NAME}"

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
    \
    sed -i '/^#\?AllowTcpForwarding.*/d' /etc/ssh/sshd_config && \
    echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config && \
    \
    sed -i '/^#\?AllowAgentForwarding.*/d' /etc/ssh/sshd_config && \
    echo "AllowAgentForwarding yes" >> /etc/ssh/sshd_config && \
    \
    sed -i '/^#\?GatewayPorts.*/d' /etc/ssh/sshd_config && \
    echo "GatewayPorts no" >> /etc/ssh/sshd_config && \
    \
    sed -i '/^#\?UsePAM.*/d' /etc/ssh/sshd_config && \
    echo "UsePAM no" >> /etc/ssh/sshd_config && \
    echo "ChallengeResponseAuthentication no" >> /etc/ssh/sshd_config && \
    \
    echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config && \
    echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config && \
    echo "LogLevel INFO" >> /etc/ssh/sshd_config

# Generate SSH host keys if they don't exist
RUN ssh-keygen -A

# Expose the SSH port
EXPOSE 22

# --- Environment Variables ---
# VPN_SERVER and VPN_USER are mandatory at runtime.
ENV VPN_TYPE="openconnect"
ENV OPENCONNECT_EXTRA_ARGS=""
ENV FORTIGATE_EXTRA_ARGS=""
ENV VPN_PASSWORD=""
ENV VPN_RECONNECT="true"
ENV VPN_RECONNECT_DELAY="5"

# Copy the entrypoint script into the image
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Check that a VPN tunnel interface exists (tun0 for openconnect, ppp0 for openfortivpn)
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD ip link show tun0 >/dev/null 2>&1 || ip link show ppp0 >/dev/null 2>&1

# Use tini to manage the entrypoint script
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/entrypoint.sh"]
