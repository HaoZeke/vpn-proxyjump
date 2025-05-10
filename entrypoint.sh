#!/usr/bin/env sh

set -e

echo "Starting SSH daemon..."
# -vHRDl0
tcpserver -vHRDl0 0.0.0.0 2200 /usr/sbin/tinysshd -v /etc/tinyssh/keys &

echo "Starting OpenConnect interactively..."
echo "You will be prompted for your EPFL VPN password."

# # Now, execute OpenConnect in the foreground.
# # This script runs as root by default in Docker, which OpenConnect needs
# # to modify network routes and create the tun interface.
exec openconnect vpn.epfl.ch \
    -u goswami@epfl.ch \
    --useragent='AnyConnect'
