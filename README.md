# WLAN Pi Tailscale Installer

This script installs and configures Tailscale on a WLAN Pi, enables it as an
exit node, requests a TLS certificate, and exposes the internal web server
over Tailscale HTTPS.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/thatsthequy/wlanpi-tailscale/652c54648bce45a9ff63747d377cf085e2aaeedc/install.sh | sudo sh | sudo sh
