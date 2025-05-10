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
    tinyssh \
    ucspi-tcp6 \
    bash \
    doas \
    ca-certificates

# Create a non-root user for SSH connections INTO the container
RUN adduser -D -s /bin/bash "${SSH_USER_NAME}"

# Setup SSH for this user using the public key provided at build time
RUN mkdir -p "/home/${SSH_USER_NAME}/.ssh" && \
    chmod 700 "/home/${SSH_USER_NAME}/.ssh" && \
    echo "${USER_PUBLIC_KEY}" > "/home/${SSH_USER_NAME}/.ssh/authorized_keys" && \
    chmod 600 "/home/${SSH_USER_NAME}/.ssh/authorized_keys" && \
    chown -R "${SSH_USER_NAME}:${SSH_USER_NAME}" "/home/${SSH_USER_NAME}/.ssh"

# Configure doas: allow SSH_USER_NAME to run openconnect as root without a password.
# This rule allows openconnect with any arguments. For tighter security, you could restrict args.
RUN echo "permit nopass ${SSH_USER_NAME} as root cmd /usr/sbin/openconnect" > /etc/doas.conf && \
    chown root:root /etc/doas.conf && chmod 0400 /etc/doas.conf

# Generate host-keys
RUN tinysshd-makekey /etc/tinyssh/keys

# Expose the SSH port
EXPOSE 2200

# Copy the entrypoint script into the image
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Use tini to manage the entrypoint script. The script itself runs as root.
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/entrypoint.sh"]
