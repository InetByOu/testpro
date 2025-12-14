#!/bin/bash
# DarkHole Ultimate v5 - SoftEther VPN Manager
# Admin default password: gstgg47e
# Hub: DarkHole
# Full ZiVPN-like functionality

VPN_DIR="/usr/local/vpnserver"
VPN_CMD="$VPN_DIR/vpncmd"
HUB_NAME="DarkHole"
ADMIN_PASSWORD="gstgg47e"
JSON_FILE="$VPN_DIR/darkhole_users.json"

# Default users
USERS=(
    "user1:pass1"
    "user2:pass2"
    "test:testing123"
)

set -e

# --- Dependencies ---
for cmd in jq ufw iptables; do
    if ! command -v $cmd &> /dev/null; then
        echo "Installing $cmd..."
        apt update && apt install -y $cmd
    fi
done

# --- Users JSON ---
if [ ! -f "$JSON_FILE" ]; then
    echo '{"users":[]}' > "$JSON_FILE"
fi

# --- Helper functions ---
run_vpncmd() {
    $VPN_CMD localhost /SERVER /HUB:$HUB_NAME /CMD "$1"
}

# --- Setup Hub + NAT + Listener ---
setup_hub() {
    echo "=== Setting up Hub $HUB_NAME ==="
    HUB_EXIST=$($VPN_CMD localhost /SERVER /CMD HubList | grep -w "$HUB_NAME" || true)
    if [ -z "$HUB_EXIST" ]; then
        $VPN_CMD localhost /SERVER /CMD HubCreate $HUB_NAME /PASSWORD:$ADMIN_PASSWORD
        echo "Hub $HUB_NAME created."
    fi
    run_vpncmd "SecureNatEnable"

    # Auto create listeners
    for port in 443 500 4500; do
        EXIST=$(run_vpncmd "ListenerList" | grep -w "$port" || true)
        if [ -z "$EXIST" ]; then
            run_vpncmd "ListenerCreate $port"
            echo "Listener $port created."
        fi
    done
}

setup_users() {
    echo "=== Setting up default users ==="
    for u in "${USERS[@]}"; do
        IFS=":" read -r username password <<< "$u"
        EXIST=$(run_vpncmd "UserList" | grep -w "$username" || true)
        if [ -z "$EXIST" ]; then
            run_vpncmd "UserCreate $username"
        fi
        run_vpncmd "UserPasswordSet $username $password"
        jq --arg u "$username" --arg p "$password" '.users |= map(select(.username != $u)) + [{"username":$u,"password":$p}]' $JSON_FILE > $JSON_FILE.tmp && mv $JSON_FILE.tmp $JSON_FILE
        echo "User $username added/updated."
    done
}

setup_nat() {
    echo "=== Setting up NAT / firewall ==="
    SYS_IF=$(ip -4 route ls|grep default|awk '{print $5}'|head -1)
    iptables -t nat -A POSTROUTING -s 10.66.66.0/24 -o $SYS_IF -j MASQUERADE || true
    ufw allow 443/tcp
    ufw allow 500/udp
    ufw allow 4500/udp
}

# --- Menu functions ---
add_update_user() {
    read -p "Enter username: " USERNAME
    read -p "Enter password: " PASSWORD
    EXIST=$(run_vpncmd "UserList" | grep -w "$USERNAME" || true)
    if [ -z "$EXIST" ]; then
        run_vpncmd "UserCreate $USERNAME"
    fi
    run_vpncmd "UserPasswordSet $USERNAME $PASSWORD"
    jq --arg u "$USERNAME" --arg p "$PASSWORD" '.users |= map(select(.username != $u)) + [{"username":$u,"password":$p}]' $JSON_FILE > $JSON_FILE.tmp && mv $JSON_FILE.tmp $JSON_FILE
    echo "User $USERNAME added/updated."
}

remove_user() {
    read -p "Enter username to remove: " USERNAME
    run_vpncmd "UserDelete $USERNAME"
    jq --arg u "$USERNAME" '.users |= map(select(.username != $u))' $JSON_FILE > $JSON_FILE.tmp && mv $JSON_FILE.tmp $JSON_FILE
    echo "User $USERNAME removed."
}

list_users() {
    echo "=== Users in Hub $HUB_NAME ==="
    run_vpncmd "UserList"
}

hub_status() {
    echo "=== Hub $HUB_NAME Status ==="
    run_vpncmd "HubStatus"
}

service_status() {
    STATUS=$(systemctl is-active vpnserver && echo "Running" || echo "Stopped")
    echo "=== DarkHole VPN Server Status ==="
    echo "Service: $STATUS"
    TOTAL_USER=$(jq '.users | length' $JSON_FILE)
    echo "Total users: $TOTAL_USER"
    ONLINE_USERS=$(run_vpncmd "SessionList" | grep -c "User Name")
    echo "Users online: $ONLINE_USERS"
    echo "=== Active listeners ==="
    run_vpncmd "ListenerList"
    echo "=== NAT / Port Forwarding Rules ==="
    iptables -t nat -L -n -v | grep MASQUERADE || echo "No NAT rules"
}

start_service() { sudo systemctl start vpnserver && echo "VPN Server started."; }
stop_service() { sudo systemctl stop vpnserver && echo "VPN Server stopped."; }
restart_service() { sudo systemctl restart vpnserver && echo "VPN Server restarted."; }

# --- Initial Setup ---
echo "=== DarkHole Ultimate v5 Setup Starting ==="
setup_hub
setup_users
setup_nat
start_service
echo "=== DarkHole VPN Setup Complete ==="

# --- Interactive Menu ---
while true; do
    echo "=============================================="
    echo " DarkHole VPN Manager v5"
    echo " Hub: $HUB_NAME | Admin: $ADMIN_PASSWORD"
    echo "=============================================="
    echo "1) Add/Update User"
    echo "2) Remove User"
    echo "3) List Users"
    echo "4) Hub Status"
    echo "5) VPN Service Status"
    echo "6) Start VPN Server"
    echo "7) Stop VPN Server"
    echo "8) Restart VPN Server"
    echo "9) Exit"
    read -p "Choose an option: " OPTION

    case $OPTION in
        1) add_update_user ;;
        2) remove_user ;;
        3) list_users ;;
        4) hub_status ;;
        5) service_status ;;
        6) start_service ;;
        7) stop_service ;;
        8) restart_service ;;
        9) exit 0 ;;
        *) echo "Invalid option" ;;
    esac
done
