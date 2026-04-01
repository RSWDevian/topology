#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  MeshLink — WireGuard Installer (Linux / Ubuntu)
#  Usage:
#    Host   → sudo bash install.sh --role host
#    Member → sudo bash install.sh --role member
# ─────────────────────────────────────────────────────────────

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()     { echo -e "${GREEN}[✔]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $1"; }
error()   { echo -e "${RED}[✘]${RESET} $1"; exit 1; }
section() { echo -e "\n${CYAN}${BOLD}── $1 ──${RESET}"; }

ROLE="member"
WG_PORT=51820
WG_IFACE="wg0"
WG_DIR="/etc/wireguard"
BACKEND_PORT=3000

while [[ $# -gt 0 ]]; do
  case $1 in
    --role) ROLE="$2"; shift 2 ;;
    --port) WG_PORT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  error "Run as root: sudo bash install.sh --role ${ROLE}"
fi

echo -e "${BOLD}"
echo "  ╔╦╗╔═╗╔═╗╦ ╦╦  ╦╔╗╔╦╔═"
echo "  ║║║║╣ ╚═╗╠═╣║  ║║║║╠╩╗"
echo "  ╩ ╩╚═╝╚═╝╩ ╩╩═╝╩╝╚╝╩ ╩  WireGuard Setup"
echo -e "${RESET}"
echo -e "  OS     : ${BOLD}Linux (Ubuntu/Debian)${RESET}"
echo -e "  Role   : ${BOLD}${ROLE}${RESET}"
echo -e "  WG Port: ${BOLD}${WG_PORT}${RESET}"
echo ""

# ── 1. Install packages ──────────────────────────────────────
section "1. Installing WireGuard & dependencies"
apt-get update -qq
apt-get install -y wireguard wireguard-tools ufw curl net-tools

if ! command -v wg &>/dev/null; then
  error "wg command not found after install"
fi
log "WireGuard installed: $(wg --version)"

# ── 2. IP forwarding ─────────────────────────────────────────
section "2. Enabling IP forwarding"
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  sysctl -p /etc/sysctl.conf -q
  log "IP forwarding enabled"
else
  log "IP forwarding already enabled"
fi

# ── 3. UFW firewall ──────────────────────────────────────────
section "3. Configuring UFW firewall"
ufw allow 22/tcp    comment "SSH"             > /dev/null
ufw allow ${WG_PORT}/udp comment "WireGuard"  > /dev/null
ufw allow ${BACKEND_PORT}/tcp comment "MeshLink backend" > /dev/null
ufw allow 80/tcp    comment "HTTP"            > /dev/null
ufw allow 443/tcp   comment "HTTPS"           > /dev/null
ufw --force enable > /dev/null
log "UFW configured and enabled"
ufw status numbered

# ── 4. WireGuard directory ───────────────────────────────────
section "4. Preparing WireGuard directory"
mkdir -p ${WG_DIR}
chmod 700 ${WG_DIR}
log "Directory ready: ${WG_DIR}"

# ── 5. Host-only: Docker + Node.js ───────────────────────────
if [[ "$ROLE" == "host" ]]; then
  section "5. Installing Node.js & Docker (host only)"

  if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null
    apt-get install -y nodejs > /dev/null
    log "Node.js installed: $(node --version)"
  else
    log "Node.js already present: $(node --version)"
  fi

  if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | bash > /dev/null
    systemctl enable docker && systemctl start docker
    log "Docker installed"
  else
    log "Docker already present: $(docker --version)"
  fi

  if ! docker compose version &>/dev/null 2>&1; then
    apt-get install -y docker-compose-plugin > /dev/null
  fi
  log "Docker Compose: $(docker compose version)"
fi

# ── 6. Auto-start on boot ────────────────────────────────────
section "6. Registering WireGuard for auto-start"
systemctl enable wg-quick@${WG_IFACE} 2>/dev/null || true
log "wg-quick@${WG_IFACE} will auto-start on boot"

# ── 7. wg-reload helper ──────────────────────────────────────
section "7. Installing wg-reload helper"
cat > /usr/local/bin/wg-reload << 'SCRIPT'
#!/bin/bash
IFACE="${1:-wg0}"
CONFIG="/etc/wireguard/${IFACE}.conf"
if [ ! -f "$CONFIG" ]; then echo "Config not found: $CONFIG"; exit 1; fi
if ip link show "$IFACE" &>/dev/null; then
  wg syncconf "$IFACE" <(wg-quick strip "$IFACE")
  echo "WireGuard $IFACE hot-reloaded"
else
  wg-quick up "$IFACE"
  echo "WireGuard $IFACE started"
fi
SCRIPT
chmod +x /usr/local/bin/wg-reload
log "wg-reload installed at /usr/local/bin/wg-reload"

# ── 8. Sudoers for backend ───────────────────────────────────
section "8. Setting up sudo rules for backend"
SUDOERS_FILE="/etc/sudoers.d/meshlink"
cat > ${SUDOERS_FILE} << SUDOERS
# MeshLink — backend WireGuard control (no password)
www-data ALL=(ALL) NOPASSWD: /usr/bin/wg
www-data ALL=(ALL) NOPASSWD: /usr/bin/wg-quick
www-data ALL=(ALL) NOPASSWD: /usr/local/bin/wg-reload
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/wg
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/wg-quick
$(whoami) ALL=(ALL) NOPASSWD: /usr/local/bin/wg-reload
SUDOERS
chmod 440 ${SUDOERS_FILE}
log "Sudoers rules written"

# ── 9. Summary ───────────────────────────────────────────────
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "unknown")
LOCAL_IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${BOLD}════════════════════════════════════════${RESET}"
echo -e "${GREEN}  ✔ Installation complete! (Linux)${RESET}"
echo -e "${BOLD}════════════════════════════════════════${RESET}"
echo -e "  Role       : ${BOLD}${ROLE}${RESET}"
echo -e "  Public IP  : ${BOLD}${PUBLIC_IP}${RESET}"
echo -e "  Local IP   : ${BOLD}${LOCAL_IP}${RESET}"
echo -e "  WG Port    : ${BOLD}${WG_PORT}/UDP${RESET}"
echo -e "  Config dir : ${BOLD}${WG_DIR}${RESET}"
echo ""
if [[ "$ROLE" == "host" ]]; then
  echo -e "${YELLOW}  Next steps (Host):${RESET}"
  echo -e "  1. Forward UDP ${WG_PORT} on router → ${LOCAL_IP}"
  echo -e "  2. cd topology && docker compose up -d"
  echo -e "  3. Open http://localhost → Host Setup"
else
  echo -e "${YELLOW}  Next steps (Member):${RESET}"
  echo -e "  1. Get the frontend URL from your host"
  echo -e "  2. Open it → Member Setup → fill in host details"
  echo -e "  3. Click Apply — WireGuard will start automatically"
fi
echo ""