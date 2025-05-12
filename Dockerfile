FROM alpine:latest

LABEL maintainer="rgoswami[at]ieee[dot]org"
LABEL description="Alpine jumphost: OpenConnect (interactive) as main process, OpenSSH server for ProxyJump."

ARG SSH_USER_NAME=jumphostuser
# It's safer to pass the public key content at build time than to have a default here that might be forgotten.
ARG USER_PUBLIC_KEY
ARG PASS=nothing

# Install necessary packages
RUN apk add --no-cache \
    tini \
    openconnect \
    openssh \
    vpnc \
    socat \
    mosh \
    openssh-server \
    bash \
    ca-certificates

# Create a non-root user for SSH connections INTO the container
# The password isn't really ever required, but causes an error without it
RUN adduser -g "${SSH_USER_NAME}" -D -s /bin/bash "${SSH_USER_NAME}" && \
    echo "${SSH_USER_NAME}:$(openssl passwd -1 $PASS)" | chpasswd

# Setup SSH for this user using the public key provided at build time
RUN mkdir -p "/home/${SSH_USER_NAME}/.ssh" && \
    chmod 700 "/home/${SSH_USER_NAME}/.ssh" && \
    echo "${USER_PUBLIC_KEY}" > "/home/${SSH_USER_NAME}/.ssh/authorized_keys" && \
    chmod 600 "/home/${SSH_USER_NAME}/.ssh/authorized_keys" && \
    chown -R "${SSH_USER_NAME}:${SSH_USER_NAME}" "/home/${SSH_USER_NAME}/.ssh"

# Configure SSHD for security and ProxyJump functionality
RUN sed -i 's/^#?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    \
    # Robustly set AllowTcpForwarding to yes
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
    echo "LogLevel DEBUG3" >> /etc/ssh/sshd_config

# Generate SSH host keys if they don't exist
RUN ssh-keygen -A

# Expose the SSH port
EXPOSE 22

# --- Environment Variables for OpenConnect ---
# These can be overridden at 'docker run' time.
# VPN_SERVER and VPN_USER are mandatory and should be set by the user at runtime for a generic image.
# ENV VPN_SERVER="" # No default, user must set
# ENV VPN_USER=""   # No default, user must set
# e.g. --useragent=AnyConnect
ENV OPENCONNECT_EXTRA_ARGS=""

# Copy the entrypoint script into the image
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Use tini to manage the entrypoint script. The script itself runs as root.
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/entrypoint.sh"]
