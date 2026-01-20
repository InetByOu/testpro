#!/bin/bash

MANAGER="/etc/zivpn/manager.json"
NOW=$(date +%s)

jq --argjson now "$NOW" \
  '.passwords |= map(select(.expire==0 or .expire>$now))' \
  "$MANAGER" > /tmp/ziman && mv /tmp/ziman "$MANAGER"

/etc/zivpn/ziman-sync.sh
