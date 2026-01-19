#!/bin/bash
# ZiVPN Manager Realtime Daemon

BASE_DIR=/opt/zivpn
source "$BASE_DIR/env.conf"
source "$BASE_DIR/lib/config.sh"
source "$BASE_DIR/lib/firewall.sh"

CFG="$ZIVPN_ETC/config.json"
DB="$BASE_DIR/passwords.db"
STATE="$BASE_DIR/.state"

mkdir -p "$BASE_DIR/logs"

hash_state() {
  sha256sum "$CFG" "$DB" 2>/dev/null | sha256sum | cut -d' ' -f1
}

last=""
[[ -f "$STATE" ]] && last=$(cat "$STATE")

while true; do
  now=$(hash_state)

  # 1️⃣ Password expired / config mismatch
  if [[ "$now" != "$last" ]]; then
    generate_config
    firewall_apply
    systemctl restart "$SERVICE_NAME"
    echo "$now" > "$STATE"
  fi

  # 2️⃣ Service mati → hidupkan
  if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    systemctl start "$SERVICE_NAME"
  fi

  sleep 5
done
