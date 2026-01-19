#!/bin/bash
# ZiVPN Manager - Production Installer
# Dynamic / Non-static / Binary-aware

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  apt update -y && apt install -y jq
fi

BASE=/opt/zivpn
LIB=$BASE/lib
LOG=$BASE/logs
ETC=/etc/zivpn

if [ ! -x /usr/local/bin/zivpn ]; then
  echo "ZiVPN binary not found at /usr/local/bin/zivpn"
  exit 1
fi

mkdir -p $LIB $LOG

cat > $BASE/env.conf <<'EOF'
BASE_DIR=/opt/zivpn
ZIVPN_BIN=/usr/local/bin/zivpn
ZIVPN_ETC=/etc/zivpn
SERVICE_NAME=zivpn
EOF

cat > $BASE/passwords.db <<'EOF'
# password|expire_epoch|note
# expire_epoch=0 means never expire
EOF

cat > $LIB/core.sh <<'EOF'
#!/bin/bash
log() {
  mkdir -p "$BASE_DIR/logs"
  echo "[$(date '+%F %T')] $*" | tee -a "$BASE_DIR/logs/manager.log"
}
pause() { read -p "Press Enter..."; }
require_root() { [ "$EUID" -eq 0 ] || exit 1; }
check_binary() { [ -x "$ZIVPN_BIN" ] || exit 1; }
EOF

cat > $LIB/config.sh <<'EOF'
#!/bin/bash
generate_config() {
  local now=$(date +%s)
  local json=""
  while IFS='|' read -r pw exp note; do
    [[ -z "$pw" || "$pw" =~ ^# ]] && continue
    [[ "$exp" -eq 0 || "$exp" -gt "$now" ]] && json+="\"$pw\","
  done < "$BASE_DIR/passwords.db"
  json="[${json%,}]"
  mkdir -p "$ZIVPN_ETC"
  local port
  if [[ -f "$ZIVPN_ETC/config.json" ]]; then
    port=$(jq -r '.listen' "$ZIVPN_ETC/config.json" | cut -d: -f2)
  fi
  [[ -z "$port" || "$port" == "null" ]] && port=$(shuf -i20000-45000 -n1)
  cat > "$ZIVPN_ETC/config.json" <<EOF2
{
  "listen": ":$port",
  "cert": "$ZIVPN_ETC/zivpn.crt",
  "key": "$ZIVPN_ETC/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": $json
  }
}
EOF2
}
EOF

cat > $LIB/password.sh <<'EOF'
#!/bin/bash
add_password() {
  local pw="$1" dur="$2"
  [[ "$pw" == *" "* ]] && return
  local exp=0
  [[ "$dur" != "0" ]] && exp=$(date -d "+$dur" +%s)
  grep -q "^$pw|" "$BASE_DIR/passwords.db" && return
  echo "$pw|$exp|" >> "$BASE_DIR/passwords.db"
  generate_config
  systemctl restart "$SERVICE_NAME"
}
del_password() {
  sed -i "/^$1|/d" "$BASE_DIR/passwords.db"
  generate_config
  systemctl restart "$SERVICE_NAME"
}
list_passwords() {
  local now=$(date +%s)
  printf "%-15s %-10s %-25s
" PASSWORD STATUS EXPIRES
  while IFS='|' read -r pw exp note; do
    [[ -z "$pw" || "$pw" =~ ^# ]] && continue
    grep -q "\"$pw\"" "$ZIVPN_ETC/config.json" && st=ACTIVE || st=INACTIVE
    [[ "$exp" -eq 0 ]] && ex="NEVER" || ex=$(date -d "@$exp")
    printf "%-15s %-10s %-25s
" "$pw" "$st" "$ex"
  done < "$BASE_DIR/passwords.db"
}
EOF

cat > $LIB/firewall.sh <<'EOF'
#!/bin/bash
firewall_apply() {
  iptables-save > "$BASE_DIR/firewall.backup"
  local port=$(jq -r '.listen' "$ZIVPN_ETC/config.json" | cut -d: -f2)
  iptables -A INPUT -p udp --dport "$port" -j ACCEPT
}
firewall_restore() {
  [[ -f "$BASE_DIR/firewall.backup" ]] && iptables-restore < "$BASE_DIR/firewall.backup"
}
EOF

cat > $LIB/service.sh <<'EOF'
#!/bin/bash
install_zivpn() {
  require_root
  check_binary
  generate_config
  firewall_apply
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
}
stop_zivpn() { systemctl stop "$SERVICE_NAME"; }
restart_zivpn() { systemctl restart "$SERVICE_NAME"; }
status_zivpn() {
  systemctl is-active "$SERVICE_NAME"
  ss -lunp | grep zivpn || true
}
uninstall_zivpn() {
  stop_zivpn
  firewall_restore
  rm -rf "$ZIVPN_ETC"
}
EOF

cat > $BASE/manager.sh <<'EOF'
#!/bin/bash
BASE_DIR=/opt/zivpn
source "$BASE_DIR/env.conf"
source "$BASE_DIR/lib/core.sh"
source "$BASE_DIR/lib/config.sh"
source "$BASE_DIR/lib/password.sh"
source "$BASE_DIR/lib/firewall.sh"
source "$BASE_DIR/lib/service.sh"

while true; do
  clear
  echo "ZiVPN Manager"
  echo "1) Install / Start"
  echo "2) Stop"
  echo "3) Restart"
  echo "4) Status"
  echo "5) Add Password"
  echo "6) Delete Password"
  echo "7) List Passwords"
  echo "0) Exit"
  read -p "> " c
  case $c in
    1) install_zivpn ;;
    2) stop_zivpn ;;
    3) restart_zivpn ;;
    4) status_zivpn ; pause ;;
    5) read -p "Password: " p; read -p "Duration (7d/0): " d; add_password "$p" "$d" ;;
    6) read -p "Password: " p; del_password "$p" ;;
    7) list_passwords ; pause ;;
    0) exit ;;
  esac
done
EOF

chmod +x $BASE/manager.sh
chmod +x $LIB/*.sh
