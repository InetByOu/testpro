#!/bin/bash
# DarkHole VPN Interactive Manager
# Admin default password: gstgg47e
# Hub: DarkHole

VPN_DIR="/usr/local/vpnserver"
VPN_CMD="$VPN_DIR/vpncmd"
HUB_NAME="DarkHole"
ADMIN_PASSWORD="gstgg47e"
JSON_FILE="$VPN_DIR/darkhole_users.json"

set -e

# --- Install jq if not present ---
if ! command -v jq &> /dev/null; then
    echo "jq not found, installing..."
    apt update && apt install -y jq
fi

# --- Ensure users JSON exists ---
if [ ! -f "$JSON_FILE" ]; then
    echo "Creating default darkhole_users.json"
    cat <<EOL > "$JSON_FILE"
{
  "users": [
    { "username": "user1", "password": "pass1" }
  ]
}
EOL
fi

# --- Functions ---

function add_update_user() {
    echo -n "Enter username: "
    read USERNAME
    echo -n "Enter password: "
    read PASSWORD

    USER_EXIST=$($VPN_CMD <<EOF
Hub $HUB_NAME
UserList
EOF
)
    if echo "$USER_EXIST" | grep -q "$USERNAME"; then
        echo "Updating password for $USERNAME..."
        $VPN_CMD <<EOF
Hub $HUB_NAME
UserPasswordSet $USERNAME $PASSWORD
EOF
    else
        echo "Creating new user $USERNAME..."
        $VPN_CMD <<EOF
Hub $HUB_NAME
UserCreate $USERNAME
UserPasswordSet $USERNAME $PASSWORD
EOF
    fi

    jq --arg u "$USERNAME" --arg p "$PASSWORD" '
    .users |= map(select(.username != $u)) + [{"username":$u,"password":$p}]
    ' $JSON_FILE > $JSON_FILE.tmp && mv $JSON_FILE.tmp $JSON_FILE

    echo "User $USERNAME added/updated successfully."
}

function remove_user() {
    echo -n "Enter username to remove: "
    read USERNAME

    $VPN_CMD <<EOF
Hub $HUB_NAME
UserDelete $USERNAME
EOF

    jq --arg u "$USERNAME" '.users |= map(select(.username != $u))' $JSON_FILE > $JSON_FILE.tmp && mv $JSON_FILE.tmp $JSON_FILE

    echo "User $USERNAME removed successfully."
}

function list_users() {
    echo "=== Users in Hub $HUB_NAME ==="
    $VPN_CMD <<EOF
Hub $HUB_NAME
UserList
EOF
}

function hub_status() {
    echo "=== Hub $HUB_NAME Status ==="
    $VPN_CMD <<EOF
Hub $HUB_NAME
HubStatus
EOF
}

function service_status() {
    echo "=== DarkHole VPN Server Status ==="
    systemctl is-active --quiet vpnserver && STATUS="Running" || STATUS="Stopped"
    echo "Service: $STATUS"

    TOTAL_USER=$(jq '.users | length' $JSON_FILE)
    echo "Total users: $TOTAL_USER"

    echo "=== Active listeners ==="
    $VPN_CMD <<EOF
Hub $HUB_NAME
ListenerList
EOF

    SERVER_IF=$(ip -4 route ls|grep default|awk '{print $5}'|head -1)
    echo "=== NAT / Port Forwarding Rules ==="
    iptables -t nat -L -n -v | grep MASQUERADE || echo "No NAT rules found"
}

function start_service() { sudo systemctl start vpnserver && echo "DarkHole VPN Server started."; }
function stop_service() { sudo systemctl stop vpnserver && echo "DarkHole VPN Server stopped." ;}
function restart_service() { sudo systemctl restart vpnserver && echo "DarkHole VPN Server restarted." ;}

# --- Menu ---
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
