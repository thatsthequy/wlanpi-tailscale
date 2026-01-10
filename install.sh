#!/usr/bin/env bash
set -euo pipefail

# --- Helpers ---------------------------------------------------------------

log() { echo -e "[+] $*"; }
err() { echo -e "[!] $*" >&2; }

ensure_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "Command '$1' not found and is required."
        exit 1
    fi
}

# --- Install Tailscale -----------------------------------------------------

install_tailscale() {
    if command -v tailscale >/dev/null 2>&1; then
        log "Tailscale already installed, skipping installation."
        return
    fi

    log "Installing Tailscale…"
    curl -fsSL https://tailscale.com/install.sh | sh
}

# --- Configure Tailscale flags --------------------------------------------

set_tailscale_flags() {
    log "Configuring Tailscale flags…"
    tailscale set \
        --advertise-exit-node \
        --accept-dns=false \
        --ssh || true
}

# --- Bring Tailscale up with QR auth --------------------------------------

bring_tailscale_up() {
    if tailscale status >/dev/null 2>&1; then
        log "Tailscale already up."
    else
        log "Starting Tailscale (scan the QR code to authenticate)…"
        tailscale up --qr
    fi
}

# --- Obtain FQDN from Tailscale state -------------------------------------

get_fqdn() {
    log "Detecting Tailscale FQDN…"
    FQDN="$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')"

    if [[ -z "$FQDN" || "$FQDN" == "null" ]]; then
        err "Failed to detect FQDN from Tailscale status JSON."
        exit 1
    fi

    echo "$FQDN"
}

# --- Request HTTPS certificate --------------------------------------------

request_cert() {
    FQDN="$1"
    log "Requesting HTTPS certificate for $FQDN…"
    tailscale cert "$FQDN"
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
    set_tailscale_flags
    bring_tailscale_up

    FQDN="$(get_fqdn)"
    log "Detected FQDN: $FQDN"

    request_cert "$FQDN"
    configure_serve

    log "All done!"
    log "Your WLAN Pi should now be reachable via https://$FQDN"
}

main "$@"
