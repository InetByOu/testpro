#!/bin/bash

MANAGER="/etc/zivpn/manager.json"
SYNC="/etc/zivpn/ziman-sync.sh"
NOW=$(date +%s)

calc_remain() {
  diff=$(( $1 - $(date +%s) ))
  [ "$diff" -le 0 ] && echo "expired" && return
  d=$((diff/86400))
  h=$((diff%86400/3600))
  m=$((diff%3600/60))
  printf "%dd %02dh %02dm" "$d" "$h" "$m"
}

clear
STATUS=$(systemctl is-active zivpn.service 2>/dev/null)
[ "$STATUS" = "active" ] && STATUS="AKTIF" || STATUS="NONAKTIF"

echo "=================================="
echo " ZiVPN Manager (ZIManager)"
echo " Status ZiVPN : $STATUS"
echo "=================================="
echo "1) Tambah password"
echo "2) List & hapus password"
echo "3) Keluar"
read -p "Pilih: " MENU

# === TAMBAH PASSWORD ===
if [ "$MENU" = "1" ]; then
  read -p "Password: " PASS
  echo "Masa aktif:"
  echo "1) 3 Hari"
  echo "2) 7 Hari"
  echo "3) 1 Bulan"
  echo "4) 1 Tahun"
  read -p "Pilih: " OPT

  case $OPT in
    1) EXP=$((NOW+3*86400)); DUR="3d" ;;
    2) EXP=$((NOW+7*86400)); DUR="7d" ;;
    3) EXP=$((NOW+30*86400)); DUR="30d" ;;
    4) EXP=$((NOW+365*86400)); DUR="365d" ;;
    *) exit 1 ;;
  esac

  jq --arg p "$PASS" --argjson e "$EXP" --arg d "$DUR" \
    '.passwords += [{"value":$p,"expire":$e,"duration":$d}]
     | .passwords |= unique_by(.value)' \
    "$MANAGER" > /tmp/ziman && mv /tmp/ziman "$MANAGER"

  "$SYNC"
  echo "✔ Password ditambahkan"
  exit 0
fi

# === LIST & DELETE ===
if [ "$MENU" = "2" ]; then
  mapfile -t LIST < <(jq -r '.passwords[].value' "$MANAGER")
  i=1
  for p in "${LIST[@]}"; do
    exp=$(jq -r ".passwords[]|select(.value==\"$p\")|.expire" "$MANAGER")
    dur=$(jq -r ".passwords[]|select(.value==\"$p\")|.duration" "$MANAGER")
    echo "$i) pass       : $p"
    echo "   masaaktif : $dur"
    echo "   expired on: $(calc_remain "$exp")"
    echo
    i=$((i+1))
  done

  read -p "Hapus nomor (Enter batal): " DEL
  [ -z "$DEL" ] && exit 0
  TARGET="${LIST[$((DEL-1))]}"

  jq --arg p "$TARGET" \
    '.passwords |= map(select(.value!=$p))' \
    "$MANAGER" > /tmp/ziman && mv /tmp/ziman "$MANAGER"

  "$SYNC"
  echo "✔ Password dihapus"
fi
