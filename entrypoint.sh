#!/usr/bin/env sh

set -e

# --- OpenConnect Configuration ---
# Check for mandatory environment variables
if [ -z "${VPN_SERVER}" ]; then
    echo "Error: VPN_SERVER environment variable is not set." >&2
    echo "Please set it using -e VPN_SERVER=\"your.vpn.server.com\" in your docker run command." >&2
    exit 1
fi

if [ -z "${VPN_USER}" ]; then
    echo "Error: VPN_USER environment variable is not set." >&2
    echo "Please set it using -e VPN_USER=\"your_vpn_username\" in your docker run command." >&2
    exit 1
fi
echo "Starting SSH daemon..."
/usr/sbin/sshd -e

echo "SSH daemon active. Starting OpenConnect interactively..."

# Use provided ENV vars, with script-level defaults for some if not set by ENV
# (though Dockerfile ENV provides defaults for USER_AGENT and SCRIPT_PATH)
VPN_SERVER_ADDR="${VPN_SERVER}"
VPN_LOGIN_USER="${VPN_USER}"
CONNECT_EXTRA_ARGS="${OPENCONNECT_EXTRA_ARGS}"

echo "Starting OpenConnect interactively for server: ${VPN_SERVER_ADDR}"
echo "Attempting login as user: ${VPN_LOGIN_USER}"
echo "You will be prompted for your VPN password."
if [ -n "$CONNECT_EXTRA_ARGS" ]; then
    echo "Using additional OpenConnect arguments: ${CONNECT_EXTRA_ARGS}"
fi

# Now, execute OpenConnect in the foreground.
# This script runs as root by default in Docker, which OpenConnect needs
# to modify network routes and create the tun interface.
# The --script flag is vital for DNS/routing updates.
if [ -n "$CONNECT_EXTRA_ARGS" ]; then
exec openconnect \
     "${VPN_SERVER_ADDR}" \
     -u "${VPN_LOGIN_USER}" \
     --script=/etc/vpnc/vpnc-script \
     "${CONNECT_EXTRA_ARGS}"
else
exec openconnect \
     "${VPN_SERVER_ADDR}" \
     -u "${VPN_LOGIN_USER}" \
     --script=/etc/vpnc/vpnc-script
fi
