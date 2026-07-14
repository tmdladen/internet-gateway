#!/bin/bash
set -e

###############################################################################
#  DeupGaming - Inner VM Full Setup
#  redsocks + cloudflared tunnel through host Gost bridge
#
#  Host gateway: 10.0.2.2 (QEMU default)
#  Powered by: DeupGaming
###############################################################################

R="\033[1;31m"; G="\033[1;32m"; Y="\033[1;33m"; B="\033[1;34m"; C="\033[1;36m"; N="\033[0m"

if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}[!] Run as root${N}"; exit 1
fi
export DEBIAN_FRONTEND=noninteractive
trap 'kill $(jobs -p) 2>/dev/null; exit 1' INT TERM

echo -e "${C}══════════════════════════════════════════${N}"
echo -e "${Y}  DeupGaming — Inner VM Full Setup${N}"
echo -e "${C}  v1.3${N}"
echo -e "${C}══════════════════════════════════════════${N}"
echo ""

# ─── Get token ──────────────────────────────────────────────────────
echo -e "${B}[?] Enter your Cloudflare Tunnel token:${N}"
echo -ne "${C}----Input--->${N} "
if [ -t 0 ]; then
  read TOKEN
else
  TTY=$(ps h -o tty -p $$ 2>/dev/null | tr -d ' ')
  if [ -n "$TTY" ] && [ -r "/dev/$TTY" ]; then
    read TOKEN < "/dev/$TTY"
  else
    read TOKEN </dev/tty 2>/dev/null || true
  fi
fi

if [ -z "$TOKEN" ]; then
  echo -e "${R}[!] Token is required.${N}"
  exit 1
fi
echo -e "${G}[✓]${N} Token received"

# ─── System proxy ───────────────────────────────────────────────────
echo ""
echo -e "${B}[*] Setting system proxy...${N}"

cat > /etc/profile.d/proxy.sh << 'EOF'
export HTTP_PROXY=http://10.0.2.2:8796
export HTTPS_PROXY=http://10.0.2.2:8796
export http_proxy=http://10.0.2.2:8796
export https_proxy=http://10.0.2.2:8796
export NO_PROXY=localhost,127.0.0.1,::1
export no_proxy=localhost,127.0.0.1,::1
EOF
chmod +x /etc/profile.d/proxy.sh
source /etc/profile.d/proxy.sh
echo -e "  ${G}[✓]${N} /etc/profile.d/proxy.sh"

cat > /etc/environment << 'EOF'
HTTP_PROXY=http://10.0.2.2:8796
HTTPS_PROXY=http://10.0.2.2:8796
http_proxy=http://10.0.2.2:8796
https_proxy=http://10.0.2.2:8796
NO_PROXY=localhost,127.0.0.1,::1
no_proxy=localhost,127.0.0.1,::1
EOF
echo -e "  ${G}[✓]${N} /etc/environment"

mkdir -p /etc/apt/apt.conf.d
cat > /etc/apt/apt.conf.d/99proxy << 'EOF'
Acquire::http::Proxy "http://10.0.2.2:8796";
Acquire::https::Proxy "http://10.0.2.2:8796";
EOF
echo -e "  ${G}[✓]${N} apt proxy"

# ─── Spinner helper ────────────────────────────────────────────────
spinner() {
  local pid=$1 msg=$2; local s="/-\|"; local i=0
  echo -ne "  ${C}${msg}...${N} "
  while kill -0 "$pid" 2>/dev/null && [ $i -lt 120 ]; do
    for j in $(seq 0 3); do echo -ne "\b${s:$j:1}"; sleep 0.3; done
    i=$((i + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    echo -e "\b${R}✗${N} timeout"
    return 1
  fi
  wait "$pid"
  echo -e "\b${G}✓${N}"
}

# ─── Install packages ───────────────────────────────────────────────
echo ""
echo -e "${B}[*] Installing packages...${N}"

apt update -y >/tmp/apt-update.log 2>&1 &
spinner $! "Updating apt" || true

if ! command -v cloudflared &>/dev/null; then
  mkdir -p --mode=0755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg -o /usr/share/keyrings/cloudflare-public-v2.gpg
  echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' > /etc/apt/sources.list.d/cloudflared.list
  apt update -y >/tmp/apt-update2.log 2>&1 &
  spinner $! "Adding Cloudflare repo" || true
fi

apt install -y redsocks iptables iptables-persistent cloudflared >/tmp/apt-install.log 2>&1 &
spinner $! "Installing packages" || true
echo -e "  ${G}[✓]${N} Packages installed"

# ─── Configure redsocks ─────────────────────────────────────────────
echo ""
echo -e "${B}[*] Configuring redsocks...${N}"

cat > /etc/redsocks.conf << 'EOF'
base {
 log_debug = off;
 log_info = on;
 log = "file:/var/log/redsocks.log";
 daemon = on;
 redirector = iptables;
}
redsocks {
 local_ip = 0.0.0.0;
 local_port = 12345;
 ip = 10.0.2.2;
 port = 8796;
 type = http-connect;
}
EOF

systemctl enable redsocks 2>/dev/null || true
systemctl restart redsocks 2>/dev/null || redsocks -c /etc/redsocks.conf &
echo -e "  ${G}[✓]${N} redsocks configured and running"

# ─── iptables rules ─────────────────────────────────────────────────
echo ""
echo -e "${B}[*] Setting iptables rules...${N}"

iptables -t nat -F OUTPUT 2>/dev/null || true
iptables -t nat -A OUTPUT -p tcp --dport 7844 -j REDIRECT --to-ports 12345
iptables -t nat -A OUTPUT -p udp --dport 7844 -j REDIRECT --to-ports 12345
netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
echo -e "  ${G}[✓]${N} iptables rules saved"

# ─── Cloudflared service ────────────────────────────────────────────
echo ""
echo -e "${B}[*] Setting up cloudflared...${N}"

cloudflared service uninstall 2>/dev/null || true
cloudflared service install "$TOKEN" 2>&1 | tail -1

rm -rf /etc/systemd/system/cloudflared.service.d
mkdir -p /etc/systemd/system/cloudflared.service.d

cat > /etc/systemd/system/cloudflared.service.d/override.conf << ENDOFFILE
[Service]
Environment=TUNNEL_TRANSPORT_PROTOCOL=http2
ExecStart=
ExecStart=/usr/bin/cloudflared --no-autoupdate tunnel run --token $TOKEN
ENDOFFILE

systemctl daemon-reload
systemctl restart cloudflared 2>/dev/null || nohup cloudflared --no-autoupdate tunnel run --token "$TOKEN" &>/tmp/cloudflared.log &
sleep 3
echo -e "  ${G}[✓]${N} cloudflared started"

# ─── Summary ────────────────────────────────────────────────────────
echo ""
echo -e "${G}✓ Setup complete${N}"
echo -e "  ${C}Proxy${N}       http://10.0.2.2:8796"
echo -e "  ${C}Tunnel${N}      HTTP/2 via redsocks"
echo -e "  ${C}Branded by${N}  DeupGaming"
echo ""
echo -e "${Y}Check status:${N}"
echo -e "  systemctl status cloudflared"
echo -e "  journalctl -xeu cloudflared --no-pager -n 10"