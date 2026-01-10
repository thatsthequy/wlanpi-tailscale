# WLAN Pi Tailscale Installer

This script installs and configures Tailscale on a WLAN Pi, enables it as an
exit node, requests a TLS certificate, and exposes the internal web server
over Tailscale HTTPS.

## Quick Install

```bash
curl -fsSL https://github.com/thatsthequy/wlanpi-tailscale/blob/main/install.sh | sudo bash
