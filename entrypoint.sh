#!/usr/bin/env bash
set -euo pipefail

VPN_PID=""
SHUTDOWN_REQUESTED=0

log() {
    echo "[entrypoint] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

cleanup() {
    SHUTDOWN_REQUESTED=1
    log "Shutdown signal received, cleaning up..."
    if [ -n "${VPN_PID}" ] && kill -0 "${VPN_PID}" 2>/dev/null; then
        log "Sending SIGINT to VPN process (PID ${VPN_PID})..."
        kill -INT "${VPN_PID}" 2>/dev/null || true
        local count=0
        while kill -0 "${VPN_PID}" 2>/dev/null && [ "$count" -lt 10 ]; do
            sleep 1
            count=$((count + 1))
        done
        if kill -0 "${VPN_PID}" 2>/dev/null; then
            log "VPN process did not exit gracefully, sending SIGTERM..."
            kill -TERM "${VPN_PID}" 2>/dev/null || true
            sleep 2
            kill -KILL "${VPN_PID}" 2>/dev/null || true
        fi
    fi
    log "Shutdown complete."
    exit 0
}

# Emit credentials on stdout for piping to openconnect --passwd-on-stdin.
# Password first line, optional TOTP second line.
# All log messages go to stderr so they don't pollute the pipe.
emit_credentials() {
    local password_file="/run/secrets/vpn_password"
    local password=""
    if [ -f "${password_file}" ]; then
        log "Reading VPN password from ${password_file}"
        password="$(cat "${password_file}")"
    elif [ -n "${VPN_PASSWORD:-}" ]; then
        log "Using VPN password from env var"
        password="${VPN_PASSWORD}"
    else
        return 1
    fi

    if [ -n "${VPN_TOTP:-}" ]; then
        log "Including TOTP in credentials"
        printf '%s\n%s\n' "${password}" "${VPN_TOTP}"
    else
        printf '%s\n' "${password}"
    fi
    return 0
}

start_vpn() {
    local vpn_type="${VPN_TYPE:-openconnect}"
    local has_creds=0

    # Test if we have credentials (don't capture, just check exit code)
    if emit_credentials >/dev/null 2>&1; then
        has_creds=1
    fi

    log "Starting ${vpn_type} for server: ${VPN_SERVER}"
    log "Logging in as user: ${VPN_USER}"

    case "${vpn_type}" in
        openconnect)
            if [ -n "${OPENCONNECT_EXTRA_ARGS:-}" ]; then
                log "Extra OpenConnect args: ${OPENCONNECT_EXTRA_ARGS}"
            fi
            if [ "${has_creds}" -eq 1 ]; then
                # Pipe credentials directly -- no variable capture to avoid
                # trailing-newline stripping or log pollution.
                emit_credentials | openconnect --passwd-on-stdin \
                    "${VPN_SERVER}" \
                    -u "${VPN_USER}" \
                    --script=/etc/vpnc/vpnc-script \
                    ${OPENCONNECT_EXTRA_ARGS:-} &
            else
                log "No stored credentials; VPN will prompt interactively."
                openconnect \
                    "${VPN_SERVER}" \
                    -u "${VPN_USER}" \
                    --script=/etc/vpnc/vpnc-script \
                    ${OPENCONNECT_EXTRA_ARGS:-} &
            fi
            ;;
        openfortivpn)
            if [ -n "${FORTIGATE_EXTRA_ARGS:-}" ]; then
                log "Extra OpenFortiVPN args: ${FORTIGATE_EXTRA_ARGS}"
            fi
            if [ "${has_creds}" -eq 1 ]; then
                local password="${VPN_PASSWORD:-}"
                openfortivpn \
                    "${VPN_SERVER}" \
                    -u "${VPN_USER}" \
                    -p "${password}" \
                    ${FORTIGATE_EXTRA_ARGS:-} &
            else
                log "No stored credentials; VPN will prompt interactively."
                openfortivpn \
                    "${VPN_SERVER}" \
                    -u "${VPN_USER}" \
                    ${FORTIGATE_EXTRA_ARGS:-} &
            fi
            ;;
        *)
            log "ERROR: Unknown VPN_TYPE '${vpn_type}'. Must be 'openconnect' or 'openfortivpn'."
            exit 1
            ;;
    esac

    VPN_PID=$!
    log "VPN process started (PID ${VPN_PID})"
}

# --- Main ---

trap cleanup SIGTERM SIGINT SIGHUP

if [ -z "${VPN_SERVER:-}" ]; then
    log "ERROR: VPN_SERVER environment variable is not set."
    log "Set it using -e VPN_SERVER=\"your.vpn.server.com\" in your docker run command."
    exit 1
fi

if [ -z "${VPN_USER:-}" ]; then
    log "ERROR: VPN_USER environment variable is not set."
    log "Set it using -e VPN_USER=\"your_vpn_username\" in your docker run command."
    exit 1
fi

# Create SSH user at runtime if it does not exist
SSH_USER="${SSH_USER_NAME:-jumpuser}"
if ! id "${SSH_USER}" >/dev/null 2>&1; then
    adduser -g "${SSH_USER}" -D -s /bin/bash "${SSH_USER}"
    # Unlock account (OpenSSH 10 rejects pubkey auth for locked accounts)
    passwd -u "${SSH_USER}" 2>/dev/null || usermod -p '*' "${SSH_USER}" 2>/dev/null || true
    log "Created SSH user: ${SSH_USER}"
fi
chmod 755 "/home/${SSH_USER}"
SSH_AUTH_DIR="/home/${SSH_USER}/.ssh"
SSH_AUTH_FILE="${SSH_AUTH_DIR}/authorized_keys"
if [ -n "${SSH_AUTHORIZED_KEY:-}" ]; then
    mkdir -p "${SSH_AUTH_DIR}"
    echo "${SSH_AUTHORIZED_KEY}" > "${SSH_AUTH_FILE}"
    chmod 700 "${SSH_AUTH_DIR}"
    chmod 600 "${SSH_AUTH_FILE}"
    chown -R "${SSH_USER}:${SSH_USER}" "${SSH_AUTH_DIR}"
    log "Installed SSH authorized key for ${SSH_USER}"
elif [ ! -f "${SSH_AUTH_FILE}" ] || [ ! -s "${SSH_AUTH_FILE}" ]; then
    log "WARNING: No SSH_AUTHORIZED_KEY set and no authorized_keys file found."
    log "SSH access will not work. Set -e SSH_AUTHORIZED_KEY=\"ssh-ed25519 ...\""
fi

# Generate host keys at runtime if not already present (allows volume persistence)
HOST_KEY_DIR="/etc/ssh/host_keys"
mkdir -p "${HOST_KEY_DIR}"
for type in rsa ecdsa ed25519; do
    keyfile="${HOST_KEY_DIR}/ssh_host_${type}_key"
    if [ ! -f "${keyfile}" ]; then
        ssh-keygen -t "${type}" -f "${keyfile}" -N "" -q
        log "Generated SSH host key: ${keyfile}"
    fi
done
# Point sshd at the persistent key directory
for type in rsa ecdsa ed25519; do
    echo "HostKey ${HOST_KEY_DIR}/ssh_host_${type}_key" >> /etc/ssh/sshd_config
done

log "Starting SSH daemon..."
/usr/sbin/sshd -e
log "SSH daemon started."

# Reconnection loop
while true; do
    start_vpn

    set +e
    wait "${VPN_PID}"
    VPN_EXIT_CODE=$?
    set -e

    if [ "${SHUTDOWN_REQUESTED}" -eq 1 ]; then
        exit 0
    fi

    log "VPN process exited with code ${VPN_EXIT_CODE}."

    if [ "${VPN_RECONNECT:-true}" != "true" ]; then
        log "VPN_RECONNECT is not 'true', exiting."
        exit "${VPN_EXIT_CODE}"
    fi

    delay="${VPN_RECONNECT_DELAY:-5}"
    log "Reconnecting in ${delay} seconds..."
    sleep "${delay}"
done
