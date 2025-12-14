#!/bin/bash
# ========================================
# DarkHole WireGuard UDP Manager - Professional Menu
# Author: ChatGPT
# ========================================

WG_CONF_DIR="/etc/darkhole"
WG_CONF_FILE="$WG_CONF_DIR/wg0.conf"
CLIENT_DIR="$WG_CONF_DIR/clients"
SERVICE_NAME="darkhole"
ADMIN_PASS="gstgg47e"
VPN_SUBNET="10.66.66.0/24"
VPN_SERVER_IP="10.66.66.1"
SERVER_PORT=5667

# Colors
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

# Check if root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Please run as root${RESET}"
    exit 1
fi

# ----------------------------
# FUNCTIONS
# ----------------------------

pause() {
    read -rp "Press Enter to continue..."
}

check_service_status() {
    systemctl is-active --quiet $SERVICE_NAME
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Running${RESET}"
    else
        echo -e "${RED}Stopped${RESET}"
    fi
}

show_interface_status() {
    ip a show wg0 2>/dev/null || echo -e "${RED}Interface wg0 not found${RESET}"
}

show_nat_status() {
    SYS_IF=$(ip -4 route ls | grep default | awk '{print $5}' | head -1)
    NAT_RULE=$(iptables -t nat -L POSTROUTING -n | grep "$VPN_SUBNET" | grep "$SYS_IF")
    if [[ -n "$NAT_RULE" ]]; then
        echo -e "${GREEN}Active${RESET}"
    else
        echo -e "${RED}Inactive${RESET}"
    fi
}

start_service() {
    systemctl start $SERVICE_NAME
    echo "Starting $SERVICE_NAME..."
    sleep 1
    check_service_status
}

stop_service() {
    systemctl stop $SERVICE_NAME
    echo "Stopping $SERVICE_NAME..."
    sleep 1
    check_service_status
}

restart_service() {
    systemctl restart $SERVICE_NAME
    echo "Restarting $SERVICE_NAME..."
    sleep 1
    check_service_status
}

list_users() {
    echo -e "${CYAN}=== Users ===${RESET}"
    if [ -d "$CLIENT_DIR" ]; then
        ls "$CLIENT_DIR"
    else
        echo "No users found"
    fi
    pause
}

add_user() {
    read -rp "Enter username: " uname
    read -sp "Enter password: " upass
    echo
    CLIENT_IP_LAST=$(($(ls "$CLIENT_DIR" 2>/dev/null | wc -l) + 2))
    CLIENT_IP="10.66.66.$CLIENT_IP_LAST"
    CLIENT_PRIV=$(wg genkey)
    CLIENT_PUB=$(echo $CLIENT_PRIV | wg pubkey)

    # Add peer to server config
    cat >> "$WG_CONF_FILE" <<EOF

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = $CLIENT_IP/32
EOF

    # Save client config
    mkdir -p "$CLIENT_DIR"
    cat > "$CLIENT_DIR/$uname.conf" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $CLIENT_IP/24
DNS = 1.1.1.1

[Peer]
PublicKey = $(cat "$WG_CONF_DIR/server_public.key")
Endpoint = $(curl -s ifconfig.me):$SERVER_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    wg-quick down $WG_CONF_FILE 2>/dev/null || true
    wg-quick up $WG_CONF_FILE

    echo -e "${GREEN}User $uname added successfully!${RESET}"
    echo "Client config saved: $CLIENT_DIR/$uname.conf"
    pause
}

remove_user() {
    read -rp "Enter username to remove: " uname
    if [ -f "$CLIENT_DIR/$uname.conf" ]; then
        CLIENT_IP=$(grep Address "$CLIENT_DIR/$uname.conf" | awk '{print $3}' | cut -d/ -f1)
        sed -i "/$CLIENT_IP/,+3d" $WG_CONF_FILE
        rm -f "$CLIENT_DIR/$uname.conf"
        wg-quick down $WG_CONF_FILE 2>/dev/null || true
        wg-quick up $WG_CONF_FILE
        echo -e "${GREEN}User $uname removed successfully${RESET}"
    else
        echo -e "${RED}User not found${RESET}"
    fi
    pause
}

status_overview() {
    echo -e "${CYAN}=== DarkHole Status Overview ===${RESET}"
    echo -n "Service: "
    check_service_status
    echo -n "Interface wg0: "
    show_interface_status
    echo -n "NAT / Firewall: "
    show_nat_status
    echo -n "Total Users: "
    ls "$CLIENT_DIR" 2>/dev/null | wc -l
    pause
}

# ----------------------------
# MENU LOOP
# ----------------------------

while true; do
    clear
    echo -e "${CYAN}==========================================${RESET}"
    echo -e "${CYAN} DarkHole WireGuard UDP Manager${RESET}"
    echo -e "${CYAN} Admin: $ADMIN_PASS${RESET}"
    echo -e "${CYAN}==========================================${RESET}"
    echo "1) Add User"
    echo "2) Remove User"
    echo "3) List Users"
    echo "4) Status Overview"
    echo "5) Start VPN Service"
    echo "6) Stop VPN Service"
    echo "7) Restart VPN Service"
    echo "8) Exit"
    read -rp "Choose an option: " opt
    case $opt in
        1) add_user ;;
        2) remove_user ;;
        3) list_users ;;
        4) status_overview ;;
        5) start_service ;;
        6) stop_service ;;
        7) restart_service ;;
        8) exit 0 ;;
        *) echo -e "${RED}Invalid option${RESET}" ; pause ;;
    esac
done
