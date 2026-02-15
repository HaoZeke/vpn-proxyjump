#!/usr/bin/env bash
set -euo pipefail

VPN_PID=""
SHUTDOWN_REQUESTED=0

log() {
    echo "[entrypoint] $(date '+%Y-%m-%d %H:%M:%S') $*"
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

# Returns password on stdout. Priority: file > env var > empty (interactive).
get_vpn_password() {
    local password_file="/run/secrets/vpn_password"
    if [ -f "${password_file}" ]; then
        log "Reading VPN password from ${password_file}"
        cat "${password_file}"
        return 0
    elif [ -n "${VPN_PASSWORD:-}" ]; then
        log "Using VPN password from VPN_PASSWORD env var"
        echo "${VPN_PASSWORD}"
        return 0
    fi
    return 1
}

start_vpn() {
    local vpn_type="${VPN_TYPE:-openconnect}"
    local password=""
    local has_password=0

    if password="$(get_vpn_password)"; then
        has_password=1
    fi

    log "Starting ${vpn_type} for server: ${VPN_SERVER}"
    log "Logging in as user: ${VPN_USER}"

    case "${vpn_type}" in
        openconnect)
            if [ -n "${OPENCONNECT_EXTRA_ARGS:-}" ]; then
                log "Extra OpenConnect args: ${OPENCONNECT_EXTRA_ARGS}"
            fi
            if [ "${has_password}" -eq 1 ]; then
                if [ -n "${OPENCONNECT_EXTRA_ARGS:-}" ]; then
                    echo "${password}" | openconnect --passwd-on-stdin \
                        "${VPN_SERVER}" \
                        -u "${VPN_USER}" \
                        --script=/etc/vpnc/vpnc-script \
                        ${OPENCONNECT_EXTRA_ARGS} &
                else
                    echo "${password}" | openconnect --passwd-on-stdin \
                        "${VPN_SERVER}" \
                        -u "${VPN_USER}" \
                        --script=/etc/vpnc/vpnc-script &
                fi
            else
                log "No stored password; VPN will prompt interactively."
                if [ -n "${OPENCONNECT_EXTRA_ARGS:-}" ]; then
                    openconnect \
                        "${VPN_SERVER}" \
                        -u "${VPN_USER}" \
                        --script=/etc/vpnc/vpnc-script \
                        ${OPENCONNECT_EXTRA_ARGS} &
                else
                    openconnect \
                        "${VPN_SERVER}" \
                        -u "${VPN_USER}" \
                        --script=/etc/vpnc/vpnc-script &
                fi
            fi
            ;;
        openfortivpn)
            if [ -n "${FORTIGATE_EXTRA_ARGS:-}" ]; then
                log "Extra OpenFortiVPN args: ${FORTIGATE_EXTRA_ARGS}"
            fi
            if [ "${has_password}" -eq 1 ]; then
                if [ -n "${FORTIGATE_EXTRA_ARGS:-}" ]; then
                    openfortivpn \
                        "${VPN_SERVER}" \
                        -u "${VPN_USER}" \
                        -p "${password}" \
                        ${FORTIGATE_EXTRA_ARGS} &
                else
                    openfortivpn \
                        "${VPN_SERVER}" \
                        -u "${VPN_USER}" \
                        -p "${password}" &
                fi
            else
                log "No stored password; VPN will prompt interactively."
                if [ -n "${FORTIGATE_EXTRA_ARGS:-}" ]; then
                    openfortivpn \
                        "${VPN_SERVER}" \
                        -u "${VPN_USER}" \
                        ${FORTIGATE_EXTRA_ARGS} &
                else
                    openfortivpn \
                        "${VPN_SERVER}" \
                        -u "${VPN_USER}" &
                fi
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
