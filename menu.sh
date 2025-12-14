#!/bin/bash
# DarkHole Ultimate Installer + Manager
# Compatible SoftEther v4.44+
# Admin default password: gstgg47e
# Hub: DarkHole
# Fully automatic setup + menu

VPN_DIR="/usr/local/vpnserver"
VPN_CMD="$VPN_DIR/vpncmd"
HUB_NAME="DarkHole"
ADMIN_PASSWORD="gstgg47e"
JSON_FILE="$VPN_DIR/darkhole_users.json"

# --- Users array ---
USERS=(
    "user1:pass1"
    "user2:pass2"
    "test:testing123"
)

set -e

# --- Install dependencies ---
if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    apt update && apt install -y jq
fi

if ! command -v ufw &> /dev/null; then
    echo "Installing ufw..."
    apt update && apt install -y ufw
fi

# --- Ensure VPN server directory exists ---
if [ ! -d "$VPN_DIR" ]; then
    echo "VPN Server directory not found at $VPN_DIR"
    echo "Please install SoftEther VPN first."
    exit 1
fi

# --- Ensure users.json exists ---
if [ ! -f "$JSON_FILE" ]; then
    echo "Creating darkhole_users.json"
    cat <<EOL > "$JSON_FILE"
{
  "users": []
}
EOL
fi

# --- Helper function ---
run_vpncmd() {
    # $1 = full command string
    $VPN_CMD localhost /SERVER /HUB:$HUB_NAME /CMD "$1"
}

# --- Setup Hub + SecureNAT + Listener ---
setup_hub() {
    echo "Setting up hub $HUB_NAME..."
    # Check if hub exists
    HUB_EXIST=$($VPN_CMD localhost /SERVER /CMD HubList | grep -w "$HUB_NAME" || true)
    if [ -z "$HUB_EXIST" ]; then
        # Create hub with admin password
        $VPN_CMD localhost /SERVER /CMD HubCreate $HUB_NAME /PASSWORD:$ADMIN_PASSWORD
        echo "Hub $HUB_NAME created with admin password."
    else
        echo "Hub $HUB_NAME already exists."
    fi

    # Enable SecureNAT
    run_vpncmd "SecureNatEnable"

    # Enable listeners TCP 443 & UDP 500/4500
    for port in 443 500 4500; do
        LISTENER=$(run_vpncmd "ListenerList" | grep -w "$port" || true)
        if [ -z "$LISTENER" ]; then
            run_vpncmd "ListenerCreate $port"
            echo "Listener $port enabled."
        fi
    done
}

# --- Add multi-users ---
setup_users() {
    echo "Setting up default users..."
    for u in "${USERS[@]}"; do
        IFS=":" read -r username password <<< "$u"
        EXIST=$(run_vpncmd "UserList" | grep -w "$username" || true)
        if [ -z "$EXIST" ]; then
            run_vpncmd "UserCreate $username"
            run_vpncmd "UserPasswordSet $username $password"
            echo "User $username created."
        else
            run_vpncmd "UserPasswordSet $username $password"
            echo "User $username password updated."
        fi

        # Update JSON
        jq --arg u "$username" --arg p "$password" '
        .users |= map(select(.username != $u)) + [{"username":$u,"password":$p}]
        ' $JSON_FILE > $JSON_FILE.tmp && mv $JSON_FILE.tmp $JSON_FILE
    done
}

# --- Setup NAT / iptables ---
setup_nat() {
    echo "Setting up NAT / firewall rules..."
    SYS_IF=$(ip -4 route ls|grep default|awk '{print $5}'|head -1)
    iptables -t nat -A POSTROUTING -s 10.66.66.0/24 -o $SYS_IF -j MASQUERADE || true
    ufw allow 443/tcp
    ufw allow 500/udp
    ufw allow 4500/udp
}

# --- Menu Functions ---
add_update_user() {
    echo -n "Enter username: "
    read USERNAME
    echo -n "Enter password: "
    read PASSWORD
    EXIST=$(run_vpncmd "UserList" | grep -w "$USERNAME" || true)
    if [ -z "$EXIST" ]; then
        run_vpncmd "UserCreate $USERNAME"
        echo "User $USERNAME created."
    fi
    run_vpncmd "UserPasswordSet $USERNAME $PASSWORD"
    jq --arg u "$USERNAME" --arg p "$PASSWORD" '
    .users |= map(select(.username != $u)) + [{"username":$u,"password":$p}]
    ' $JSON_FILE > $JSON_FILE.tmp && mv $JSON_FILE.tmp $JSON_FILE
    echo "User $USERNAME added/updated."
}

remove_user() {
    echo -n "Enter username to remove: "
    read USERNAME
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
    echo "=== DarkHole VPN Server Status ==="
    systemctl is-active --quiet vpnserver && STATUS="Running" || STATUS="Stopped"
    echo "Service: $STATUS"
    TOTAL_USER=$(jq '.users | length' $JSON_FILE)
    echo "Total users: $TOTAL_USER"
    echo "=== Active listeners ==="
    run_vpncmd "ListenerList"
    echo "=== NAT / Port Forwarding Rules ==="
    iptables -t nat -L -n -v | grep MASQUERADE || echo "No NAT rules found"
}

start_service() { sudo systemctl start vpnserver && echo "VPN Server started."; }
stop_service() { sudo systemctl stop vpnserver && echo "VPN Server stopped."; }
restart_service() { sudo systemctl restart vpnserver && echo "VPN Server restarted."; }

# --- Run Setup ---
echo "=== DarkHole Ultimate Setup Starting ==="
setup_hub
setup_users
setup_nat
start_service
echo "=== DarkHole VPN Setup Complete ==="

# --- Interactive Menu ---
while true; do
    echo "=============================================="
    echo " DarkHole VPN Manager"
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
    echo -n "Choose an option: "
    read OPTION

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
