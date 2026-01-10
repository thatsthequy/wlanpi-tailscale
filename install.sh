#!/usr/bin/env bash

# If the script was started under /bin/sh (dash), re-exec under bash so we can
# safely use bash-specific features like 'set -o pipefail'.
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "This script requires bash. Please run with 'bash install.sh'." >&2
        exit 1
    fi
fi

set -euo pipefail

# --- Helpers ---------------------------------------------------------------

# Send informational logs to stderr so command substitution (which captures
# stdout) does not pick them up.
log() { echo -e "[+] $*" >&2; }
err() { echo -e "[!] $*" >&2; }

ensure_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "Command '$1' not found and is required."
        exit 1
    fi
}

# Use sudo only when needed
if [[ "$EUID" -ne 0 ]]; then
    SUDO=sudo
else
    SUDO=""
fi

# --- Install Tailscale -----------------------------------------------------

install_tailscale() {
    if command -v tailscale >/dev/null 2>&1; then
        log "Tailscale already installed, skipping installation."
        return
    fi

    log "Installing Tailscale…"
    # Run remote installer as root if not already root.
    curl -fsSL https://tailscale.com/install.sh | ${SUDO} sh
}

# --- Enable IP Forwarding for Exit Node -----------------------------------

enable_ip_forwarding() {
    log "Enabling IP forwarding for Exit Node support…"
    CONF_FILE="/etc/sysctl.d/99-tailscale.conf"

    # Create file if it doesn't exist
    ${SUDO} touch "$CONF_FILE"

    # Append if missing (idempotent)
    grep -qxF 'net.ipv4.ip_forward = 1' "$CONF_FILE" \
        || echo 'net.ipv4.ip_forward = 1' | ${SUDO} tee -a "$CONF_FILE" >/dev/null

    grep -qxF 'net.ipv6.conf.all.forwarding = 1' "$CONF_FILE" \
        || echo 'net.ipv6.conf.all.forwarding = 1' | ${SUDO} tee -a "$CONF_FILE" >/dev/null

    # Apply settings immediately
    ${SUDO} sysctl -p "$CONF_FILE"
}

# --- Wait for Tailscale to be ready --------------------------------------

wait_for_self_json() {
    # Wait up to a number of attempts for tailscale status to return JSON with Self fields
    local max_tries=60
    local try=0
    while (( try < max_tries )); do
        # shells: allow failure and capture output
        if json=$({ tailscale status --json 2>/dev/null || true; }); then
            if [[ -n "$json" && "$json" != "null" ]]; then
                printf '%s' "$json"
                return 0
            fi
        fi
        ((try++))
        log "Waiting for Tailscale to be ready (attempt $try/$max_tries)…"
        sleep 2
    done
    return 1
}

# --- Configure Tailscale flags --------------------------------------------

set_tailscale_flags() {
    log "Configuring Tailscale flags…"
    # tolerate failure so script can continue if not yet authenticated
    tailscale set --advertise-exit-node --accept-dns=false --ssh || true
    # If you want this node to accept subnet routes advertised by peers, enable:
    # tailscale set --accept-routes || true
}

# --- Bring Tailscale up with QR auth --------------------------------------

bring_tailscale_up() {
    if tailscale status >/dev/null 2>&1; then
        log "Tailscale already running."
    else
        log "Starting Tailscale (scan the QR code to authenticate)…"
        tailscale up --qr
    fi
}

# --- Obtain FQDN from Tailscale state -------------------------------------

get_fqdn() {
    log "Detecting Tailscale FQDN…"
    json="$(wait_for_self_json)" || {
        err "Timed out waiting for tailscale status JSON."
        return 1
    }

    # Prefer DNSName, fall back to Hostname or Name. Strip trailing dot if present.
    FQDN="$(printf '%s' "$json" | jq -r '.Self.DNSName // .Self.Hostname // .Self.Name // ""' | sed 's/\.$//')"

    if [[ -z "$FQDN" || "$FQDN" == "null" ]]; then
        err "Failed to detect FQDN from Tailscale status JSON."
        return 1
    fi

    echo "$FQDN"
}

# --- Request HTTPS certificate --------------------------------------------

request_cert() {
    local fqdn="$1"
    log "Requesting HTTPS certificate for $fqdn…"

    # Save combined PEM (cert+key) to a local path with restrictive permissions.
    local dest_dir="/etc/ssl/tailscale"
    local tmpfile
    tmpfile="$(mktemp)"

    if tailscale cert "$fqdn" >"$tmpfile" 2>/dev/null; then
        ${SUDO} mkdir -p "$dest_dir"
        ${SUDO} mv "$tmpfile" "$dest_dir/${fqdn}.pem"
        ${SUDO} chmod 600 "$dest_dir/${fqdn}.pem"
        log "Saved cert to $dest_dir/${fqdn}.pem (permission 600)."
    else
        rm -f "$tmpfile"
        err "tailscale cert failed for $fqdn"
        return 1
    fi
}

# --- Configure Tailscale serve --------------------------------------------

configure_serve() {
    log "Configuring Tailscale serve over port 443…"
    tailscale serve --bg https+insecure://localhost:443
}

# --- Main entry ------------------------------------------------------------

main() {
    ensure_cmd curl
    ensure_cmd jq

    install_tailscale
    enable_ip_forwarding

    bring_tailscale_up

    # Wait for tailscale to be up and reporting Self before continuing
    if ! wait_for_self_json >/dev/null; then
        err "Tailscale did not become ready in time. Ensure you completed QR authentication."
        exit 1
    fi

    set_tailscale_flags

    FQDN="$(get_fqdn)" || exit 1
    log "Detected FQDN: $FQDN"

    # Request and save a certificate (optional). Continue even if it fails.
    if ! request_cert "$FQDN"; then
        log "Warning: certificate request failed; continuing."
    fi

    configure_serve

    log "All done!"
    log "Your WLAN Pi should now be reachable via https://$FQDN"
}

main "$@"
