# DeupGaming — Gost Docker Proxy

Single-container WebSocket proxy bridge using [Gost](https://github.com/ginuerzh/gost).

## Usage (host)

```bash
curl -sS https://raw.githubusercontent.com/tmdladen/internet-gateway/main/setup.sh | sudo bash
```

You'll be prompted to enter your Gost WebSocket URL.

Format: `wss://username:password@hostname:port`

### Pass URL directly (no prompt)

```bash
GOST_URL="wss://user:pass@your-server.com:443" curl -sS https://raw.githubusercontent.com/tmdladen/internet-gateway/main/setup.sh | sudo bash
```

## Usage (inside QEMU VM)

### Web proxy only

```bash
curl -sS https://raw.githubusercontent.com/tmdladen/internet-gateway/main/inner-vm-proxy.sh | sudo bash
```

Sets `http://10.0.2.2:8796` as system proxy.

### Full setup with Cloudflare Tunnel (redsocks + cloudflared)

```bash
curl -sS https://raw.githubusercontent.com/tmdladen/internet-gateway/main/inner-vm-setup.sh | sudo bash
```

Prompts for Cloudflare tunnel token, then installs redsocks, iptables rules, and configures cloudflared with HTTP/2 through the proxy. Runs on boot.

## How it works

* Runs a Gost Docker container with `--net=host` listening on port `8796`.
* Traffic is forwarded over WebSocket Secure (`wss://`) through a Railway gateway, bypassing Cloudflare CONNECT blocks.
* System proxy is configured via `/etc/profile.d/net-way.sh`, `/etc/environment`, and `/etc/apt/apt.conf.d`.
* Auto-start via `/etc/rc.local`.
* Installs `qemu-system`, `cloud-image-utils`, `wget`, `lsof`.
* Patches QEMU `-no-hpet` flag for compatibility with QEMU 9.0+.

## After setup

Environment variables only apply to new shells. To use the proxy in the current session:

```bash
source /etc/profile.d/net-way.sh   # on host
# or
source /etc/profile.d/proxy.sh     # inside VM
```

New logins will have the proxy automatically.

## Check if it's working

```bash
curl -x http://127.0.0.1:8796 https://ifconfig.me
```

---

*Powered and Maintained by [@dev3abdullah](https://github.com/dev3abdullah)*
