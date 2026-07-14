#!/bin/bash
set -e

###############################################################################
#  DeupGaming - Gost Docker Proxy Setup
#  Single-container WebSocket bridge through Railway
#
#  Powered by: DeupGaming
###############################################################################

R="\033[1;31m"; G="\033[1;32m"; Y="\033[1;33m"; B="\033[1;34m"; C="\033[1;36m"; N="\033[0m"

# Banner
echo -e "${C}
  _  _      _       __       ___         _   _ 
 | \ | | ___| |___   \ \     / / |__   __| | | |
 |  \| |/ _ \ / __|   \ \ /\ / /| '_ \ / _\` | | |
 | |\  |  __/ \__ \    \ V  V / | | | | (_| | |_|
 |_| \_|\___|_|___/     \_/\_/  |_| |_|\__, | (_)
                                        |___/
${G}  DeupGaming — Gost Bridge${N}
${C}  v1.3${N}
${Y}  Single-container WebSocket proxy${N}
"

# Check root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}[!] Run as root (sudo)${N}"; exit 1
fi

GOST_PORT=8796

# ─── Get gost URL ──────────────────────────────────────────────────────
if [ -z "$GOST_URL" ]; then
  echo ""
  echo -e "${B}[?] Enter your Gost WebSocket URL:${N}"
  echo -e "${Y}    Format: wss://user:pass@host:port${N}"
  echo -ne "${C}----Input--->${N} "
  if [ -t 0 ]; then
    read GOST_URL
  else
    TTY=$(ps h -o tty -p $$ 2>/dev/null | tr -d ' ')
    if [ -n "$TTY" ] && [ -r "/dev/$TTY" ]; then
      read GOST_URL < "/dev/$TTY"
    else
      read GOST_URL </dev/tty 2>/dev/null || true
    fi
  fi
  if [ -z "$GOST_URL" ]; then
    echo -e "${R}[!] URL is required. Use GOST_URL env var when piping.${N}"
    exit 1
  fi
fi
echo -e "${G}[✓]${N} Gost URL: ${GOST_URL}"

# ─── Install Docker ────────────────────────────────────────────────────
echo ""
echo -e "${B}[*] Installing Docker...${N}"
if command -v docker &>/dev/null; then
  echo -e "  ${G}[✓]${N} Docker already installed: $(docker --version 2>/dev/null)"
else
  curl -fsSL https://get.docker.com | sh 2>&1 | tail -3
  dockerd &>/tmp/dockerd.log &
  sleep 3
  echo -e "  ${G}[✓]${N} Docker installed: $(docker --version 2>/dev/null)"
fi

# ─── Install packages ──────────────────────────────────────────────────
echo ""
echo -e "${B}[*] Installing system packages...${N}"
apt update -y 2>&1 | tail -1
apt install -y qemu-system cloud-image-utils wget lsof curl bash 2>&1 | tail -3
echo -e "  ${G}[✓]${N} System packages installed"

# ─── Fix QEMU -no-hpet (removed in QEMU 9.0+) ──────────────────────────
cat > /usr/local/bin/qemu-system-x86_64 << 'QWRAP'
#!/bin/bash
args=()
for arg in "$@"; do
  [[ "$arg" == "-no-hpet" ]] && continue
  args+=("$arg")
done
exec /usr/bin/qemu-system-x86_64 "${args[@]}"
QWRAP
chmod +x /usr/local/bin/qemu-system-x86_64
echo -e "  ${G}[✓]${N} QEMU -no-hpet wrapper installed"

# ─── Remove old gost container ─────────────────────────────────────────
docker rm -f gost-bridge 2>/dev/null || true

# ─── Run Gost ──────────────────────────────────────────────────────────
echo ""
echo -e "${B}[*] Starting Gost bridge on port ${GOST_PORT}...${N}"
docker run -d --net=host --restart unless-stopped \
  --name gost-bridge \
  ginuerzh/gost:latest \
  -L=:$GOST_PORT \
  -F="$GOST_URL" > /dev/null 2>&1

sleep 2

if docker ps --format '{{.Names}}' | grep -q gost-bridge; then
  echo -e "  ${G}[✓]${N} Gost bridge running on 127.0.0.1:${GOST_PORT}"
else
  echo -e "  ${R}[✗]${N} Gost failed to start. Check: docker logs gost-bridge${N}"
  docker logs gost-bridge 2>/dev/null | tail -5
  exit 1
fi

# ─── System proxy config ───────────────────────────────────────────────
echo ""
echo -e "${B}[*] Configuring system-wide proxy...${N}"

# /etc/profile.d
cat > /etc/profile.d/net-way.sh << EOF
export HTTP_PROXY=http://127.0.0.1:${GOST_PORT}
export HTTPS_PROXY=http://127.0.0.1:${GOST_PORT}
export http_proxy=http://127.0.0.1:${GOST_PORT}
export https_proxy=http://127.0.0.1:${GOST_PORT}
export NO_PROXY=localhost,127.0.0.1,::1,deb.debian.org,security.debian.org,snapshot.debian.org,archive.ubuntu.com,security.ubuntu.com,ppas.launchpadcontent.net
export no_proxy=localhost,127.0.0.1,::1,deb.debian.org,security.debian.org,snapshot.debian.org,archive.ubuntu.com,security.ubuntu.com,ppas.launchpadcontent.net
EOF
chmod +x /etc/profile.d/net-way.sh
echo -e "  ${G}[✓]${N} /etc/profile.d/net-way.sh"

# /etc/environment
cat > /etc/environment << 'EOF'
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
HTTP_PROXY=http://127.0.0.1:8796
HTTPS_PROXY=http://127.0.0.1:8796
http_proxy=http://127.0.0.1:8796
https_proxy=http://127.0.0.1:8796
NO_PROXY=localhost,127.0.0.1,::1,deb.debian.org,security.debian.org,snapshot.debian.org,archive.ubuntu.com,security.ubuntu.com,ppas.launchpadcontent.net
no_proxy=localhost,127.0.0.1,::1,deb.debian.org,security.debian.org,snapshot.debian.org,archive.ubuntu.com,security.ubuntu.com,ppas.launchpadcontent.net
EOF
echo -e "  ${G}[✓]${N} /etc/environment"

# sudoers
cat > /etc/sudoers.d/proxy << 'EOFP'
Defaults env_keep += "HTTP_PROXY HTTPS_PROXY http_proxy https_proxy NO_PROXY no_proxy"
EOFP
chmod 440 /etc/sudoers.d/proxy
echo -e "  ${G}[✓]${N} sudoers proxy preservation"

# ─── Auto-start docker + gost via rc.local ─────────────────────────────
echo ""
echo -e "${B}[*] Configuring auto-start...${N}"

if [ -f /etc/rc.local ]; then
  sed -i '/gost-bridge/d; /dockerd/d' /etc/rc.local 2>/dev/null || true
else
  echo '#!/bin/sh' > /etc/rc.local
  chmod +x /etc/rc.local
fi
sed -i '/^exit 0/i dockerd &>/tmp/dockerd.log &' /etc/rc.local 2>/dev/null || true
sed -i '/^exit 0/i docker start gost-bridge 2>/dev/null || docker run -d --net=host --restart unless-stopped --name gost-bridge ginuerzh/gost:latest -L=:8796 -F="'"$GOST_URL"'"' /etc/rc.local 2>/dev/null || true
echo -e "  ${G}[✓]${N} rc.local auto-start"

# ─── Test ──────────────────────────────────────────────────────────────
echo ""
echo -e "${B}[*] Testing...${N}"
sleep 2

export HTTP_PROXY=http://127.0.0.1:$GOST_PORT
export HTTPS_PROXY=http://127.0.0.1:$GOST_PORT

ALL_OK=1
for url in https://github.com https://google.com https://discord.com; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$url" 2>&1) || true
  if [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ] || [ "$code" = "403" ]; then
    echo -e "  ${G}[✓]${N} $url → HTTP $code"
  else
    echo -e "  ${R}[✗]${N} $url → HTTP $code"
    ALL_OK=0
  fi
done

# ─── Summary ───────────────────────────────────────────────────────────
echo ""
echo -e "${G}✓ Setup complete${N}"
echo -e "  ${C}Gost URL${N}    ${GOST_URL}"
echo -e "  ${C}Proxy${N}       http://127.0.0.1:${GOST_PORT}"
echo -e "  ${C}Branded by${N}  DeupGaming"
echo ""
echo -e "${Y}Start using it:${N}"
echo -e "  source /etc/profile.d/net-way.sh"
echo -e "  curl https://ifconfig.me"
echo ""
echo -e "${Y}Manage:${N}"
echo -e "  docker logs gost-bridge"
echo -e "  docker restart gost-bridge"
echo -e "  docker rm -f gost-bridge"

if [ "$ALL_OK" = "0" ]; then
  echo ""
  echo -e "${R}[!] Some tests failed. Check: docker logs gost-bridge${N}"
fi
echo ""