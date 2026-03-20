# WLAN Pi Tailscale Installer

This script installs and configures Tailscale on a WLAN Pi, enables Tailscale SSH, enables exit node, requests a TLS certificate, and exposes the internal web server over Tailscale serve with a valid HTTPS certificate.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/thatsthequy/wlanpi-tailscale/main/install.sh | sudo bash
