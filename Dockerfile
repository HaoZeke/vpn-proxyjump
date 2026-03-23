FROM alpine:latest

LABEL maintainer="rgoswami[at]ieee[dot]org"
LABEL description="Alpine jumphost: OpenConnect/OpenFortiVPN + OpenSSH server for ProxyJump."
LABEL org.opencontainers.image.source="https://github.com/HaoZeke/vpn-proxyjump"
LABEL org.opencontainers.image.version="2.0.0"
LABEL org.opencontainers.image.licenses="MIT"

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
    vpnc \
    socat \
    mosh \
    bash \
    ca-certificates \
    shadow

# Write a clean sshd_config
RUN cat > /etc/ssh/sshd_config <<'SSHD'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
AllowTcpForwarding yes
AllowAgentForwarding yes
GatewayPorts no
ChallengeResponseAuthentication no
ClientAliveInterval 60
ClientAliveCountMax 3
LogLevel INFO
SSHD

# Host keys generated at runtime (entrypoint) so they persist across
# image rebuilds when /etc/ssh/host_keys is volume-mounted.

# Expose the SSH port
EXPOSE 22

# --- Environment Variables ---
# VPN_SERVER and VPN_USER are mandatory at runtime.
# SSH_USER_NAME: SSH login username (created at runtime if missing).
# SSH_AUTHORIZED_KEY: public key for SSH access (injected at runtime).
ENV VPN_TYPE="openconnect"
ENV SSH_USER_NAME="jumpuser"
ENV OPENCONNECT_EXTRA_ARGS=""
ENV FORTIGATE_EXTRA_ARGS=""
ENV VPN_RECONNECT="true"
ENV VPN_RECONNECT_DELAY="5"

# Copy the entrypoint script into the image
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Check that a VPN tunnel interface exists
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD ip link show tun0 >/dev/null 2>&1 || ip link show ppp0 >/dev/null 2>&1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/entrypoint.sh"]
