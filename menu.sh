#!/bin/bash
# SoftEther VPN ZiVPN-like: Add/Update users from JSON
# Does NOT recreate hub or reset listeners
# Users loaded from users.json
# Hub: DarkHole

set -e

VPN_CMD="/usr/local/vpnserver/vpncmd"
HUB_NAME="DarkHole"
JSON_FILE="/usr/local/vpnserver/users.json"

# --- Install jq if not present ---
if ! command -v jq &> /dev/null; then
    echo "jq not found, installing..."
    apt update && apt install jq -y
fi

echo "=== Adding/Updating Users from $JSON_FILE ==="
USER_COUNT=$(jq '.users | length' $JSON_FILE)

for (( i=0; i<$USER_COUNT; i++ ))
do
    USERNAME=$(jq -r ".users[$i].username" $JSON_FILE)
    PASSWORD=$(jq -r ".users[$i].password" $JSON_FILE)

    # Check if user exists
    USER_EXIST=$($VPN_CMD <<EOF
Hub $HUB_NAME
UserList
EOF
    )

    if echo "$USER_EXIST" | grep -q "$USERNAME"; then
        echo "Updating password for existing user $USERNAME"
        $VPN_CMD <<EOF
Hub $HUB_NAME
UserPasswordSet $USERNAME $PASSWORD
EOF
    else
        echo "Creating new user $USERNAME"
        $VPN_CMD <<EOF
Hub $HUB_NAME
UserCreate $USERNAME
UserPasswordSet $USERNAME $PASSWORD
EOF
    fi
done

echo "=== All users processed successfully ==="
