#!/bin/bash
# SoftEther VPN ZiVPN-like Multi-user from JSON
# Hub: DarkHole
# SecureNAT + TCP/UDP listener + NAT/iptables
# Users loaded from users.json

set -e

VPN_CMD="/usr/local/vpnserver/vpncmd"
HUB_NAME="DarkHole"
ADMIN_PASSWORD="gstgg47e"

TCP_PORT=443
UDP_PORT1=500
UDP_PORT2=4500

JSON_FILE="/usr/local/vpnserver/users.json"

# --- Install jq if not present (to parse JSON) ---
if ! command -v jq &> /dev/null; then
    echo "jq not found, installing..."
    apt update && apt install jq -y
fi

echo "=== Configuring SoftEther VPN Server ==="

# 1️⃣ Set admin password, create hub, enable SecureNAT & listeners
$VPN_CMD <<EOF
ServerPasswordSet $ADMIN_PASSWORD
HubCreate $HUB_NAME
Hub $HUB_NAME
HubEnable
SecureNatEnable
ListenerCreate $TCP_PORT /TCP
ListenerCreate $UDP_PORT1 /UDP
ListenerCreate $UDP_PORT2 /UDP
EOF

# 2️⃣ Add users from JSON
echo "=== Adding Users from $JSON_FILE ==="
USER_COUNT=$(jq '.users | length' $JSON_FILE)

for (( i=0; i<$USER_COUNT; i++ ))
do
    USERNAME=$(jq -r ".users[$i].username" $JSON_FILE)
    PASSWORD=$(jq -r ".users[$i].password" $JSON_FILE)

    $VPN_CMD <<EOF
Hub $HUB_NAME
UserCreate $USERNAME
UserPasswordSet $USERNAME $PASSWORD
EOF
    echo "User $USERNAME created with password $PASSWORD"
done

# 3️⃣ Setup NAT + iptables
echo "=== Configuring NAT + iptables ==="
SERVER_IF=$(ip -4 route ls | grep default | awk '{print $5}' | head -1)

iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o $SERVER_IF -j MASQUERADE
ufw allow $TCP_PORT/tcp
ufw allow $UDP_PORT1/udp
ufw allow $UDP_PORT2/udp

echo "=== SoftEther ZiVPN-like configuration complete ==="
echo "Hub: $HUB_NAME | Admin Password: $ADMIN_PASSWORD"
echo "Users loaded from $JSON_FILE"
