#!/bin/bash
# SoftEther VPN ZiVPN-like Auto Configuration
# Hub: DarkHole
# Multi-user setup + SecureNAT + TCP/UDP listener + NAT/iptables

set -e

VPN_CMD="/usr/local/vpnserver/vpncmd"

# --- Server admin password ---
ADMIN_PASSWORD="DarkHoleAdmin123"

# --- Virtual Hub name ---
HUB_NAME="DarkHole"

# --- UDP/TCP listeners ---
TCP_PORT=443
UDP_PORT1=500
UDP_PORT2=4500

# --- Multi-user list (username:password) ---
declare -A USERS
USERS=( ["user1"]="pass1" ["user2"]="pass2" ["user3"]="pass3" )

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

# 2️⃣ Add multi-users
echo "=== Adding Users ==="
for USER in "${!USERS[@]}"; do
    PASSWORD=${USERS[$USER]}
    $VPN_CMD <<EOF
Hub $HUB_NAME
UserCreate $USER
UserPasswordSet $USER $PASSWORD
EOF
    echo "User $USER created with password $PASSWORD"
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
for USER in "${!USERS[@]}"; do
    echo "User: $USER | Password: ${USERS[$USER]}"
done
