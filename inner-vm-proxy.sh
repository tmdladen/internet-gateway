#!/bin/bash
set -e

###############################################################################
#  DeupGaming - Inner VM Proxy
#  System-wide proxy for QEMU VMs through host Gost bridge
#
#  Host gateway: 10.0.2.2 (QEMU default)
#  Powered by: DeupGaming
###############################################################################

R="\033[1;31m"; G="\033[1;32m"; Y="\033[1;33m"; B="\033[1;34m"; C="\033[1;36m"; N="\033[0m"

echo -e "${C}══════════════════════════════════════════${N}"
echo -e "${Y}  DeupGaming — Inner VM Proxy${N}"
echo -e "${C}  v1.3${N}"
echo -e "${C}══════════════════════════════════════════${N}"
echo ""

if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}[!] Run as root${N}"; exit 1
fi

cat > /etc/environment << 'EOF'
HTTP_PROXY=http://10.0.2.2:8796
HTTPS_PROXY=http://10.0.2.2:8796
http_proxy=http://10.0.2.2:8796
https_proxy=http://10.0.2.2:8796
NO_PROXY=localhost,127.0.0.1,::1
no_proxy=localhost,127.0.0.1,::1
EOF

mkdir -p /etc/apt/apt.conf.d
cat > /etc/apt/apt.conf.d/99proxy << 'EOF'
Acquire::http::Proxy "http://10.0.2.2:8796";
Acquire::https::Proxy "http://10.0.2.2:8796";
EOF

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

echo -e "  ${G}[✓]${N} Proxy configured: http://10.0.2.2:8796"
echo ""
echo -e "${Y}Start using it:${N}"
echo -e "  source /etc/profile.d/proxy.sh"
echo -e "  curl https://ifconfig.me"