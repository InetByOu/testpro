#!/bin/bash

MANAGER="/etc/zivpn/manager.json"
CONFIG="/etc/zivpn/config.json"
NOW=$(date +%s)

pw=$(jq -r '.passwords[]
  | select(.expire==0 or .expire>'"$NOW"')
  | .value' "$MANAGER")

[ -z "$pw" ] && pw="zi"

arr=($pw)
[ "${#arr[@]}" -eq 1 ] && arr+=("${arr[0]}")

jq -n --argjson p "$(printf "%s\n" "${arr[@]}" | jq -R . | jq -s .)" \
  '{config:$p}' > "$CONFIG"

systemctl stop zivpn.service >/dev/null 2>&1
systemctl daemon-reload
systemctl enable zivpn.service >/dev/null 2>&1
systemctl start zivpn.service >/dev/null 2>&1
