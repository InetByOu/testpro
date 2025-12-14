#!/bin/bash
# ========================================
# DarkHole WireGuard UDP Installer & Manager
# Author: ChatGPT
# ========================================

# ----------------------------
# CONFIGURATION
# ----------------------------
SERVER_PORT=5667
VPN_SUBNET="10.66.66.0/24"
VPN_SERVER_IP="10.66.66.1"
WG_CONF_DIR="/etc/darkhole"
WG_CONF_FILE="$WG_CONF_DIR/wg0.conf"
CLIENT_DIR="$WG_CONF_DIR/clients"

# Default admin password
ADMIN_PASS="gstgg47e"

# USERS array example (username:password)
declare -A USERS
USERS=( ["testuser"]="testpass" )

# ----------------------------
# FUNCTIONS
# ----------------------------

install_dependencies() {
    echo "Installing WireGuard and dependencies..."
    apt-get update && apt-get install -y wireguard iptables qrencode ufw
    mkdir -p "$WG_CONF_DIR" "$CLIENT_DIR"
}

generate_server_keys() {
    echo "Generating server keys..."
    if [ ! -f "$WG_CONF_DIR/server_private.key" ]; then
        wg genkey | tee "$WG_CONF_DIR/server_private.key" | wg pubkey > "$WG_CONF_DIR/server_public.key"
    fi
    SERVER_PRIVATE=$(cat "$WG_CONF_DIR/server_private.key")
    SERVER_PUBLIC=$(cat "$WG_CONF_DIR/server_public.key")
}

generate_server_conf() {
    echo "Generating wg0.conf..."
    cat > "$WG_CONF_FILE" <<EOF
[Interface]
Address = $VPN_SERVER_IP/24
ListenPort = $SERVER_PORT
PrivateKey = $SERVER_PRIVATE
SaveConfig = true
EOF
}

setup_nat_firewall() {
    echo "Setting up NAT & firewall..."
    SYS_IF=$(ip -4 route ls | grep default | awk '{print $5}' | head -1)
    iptables -t nat -A POSTROUTING -s $VPN_SUBNET -o $SYS_IF -j MASQUERADE
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    ufw allow $SERVER_PORT/udp
    ufw enable || true
}

create_systemd_service() {
    echo "Creating systemd service..."
    cat > /etc/systemd/system/darkhole.service <<EOF
[Unit]
Description=DarkHole WireGuard VPN
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/wg-quick up $WG_CONF_FILE
ExecStop=/usr/bin/wg-quick down $WG_CONF_FILE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable darkhole
    systemctl start darkhole
}

add_user() {
    read -p "Enter username: " uname
    read -sp "Enter password: " upass
    echo
    CLIENT_IP_LAST=$(($(ls $CLIENT_DIR | wc -l) + 2))
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
    cat > "$CLIENT_DIR/$uname.conf" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $CLIENT_IP/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUBLIC
Endpoint = $(curl -s ifconfig.me):$SERVER_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    wg-quick down $WG_CONF_FILE 2>/dev/null || true
    wg-quick up $WG_CONF_FILE
    echo "User $uname added, config: $CLIENT_DIR/$uname.conf"
}

list_users() {
    echo "=== Users ==="
    ls $CLIENT_DIR
}

remove_user() {
    read -p "Enter username to remove: " uname
    if [ -f "$CLIENT_DIR/$uname.conf" ]; then
        CLIENT_IP=$(grep Address "$CLIENT_DIR/$uname.conf" | awk '{print $3}' | cut -d/ -f1)
        sed -i "/$CLIENT_IP/,+3d" $WG_CONF_FILE
        rm -f "$CLIENT_DIR/$uname.conf"
        wg-quick down $WG_CONF_FILE 2>/dev/null || true
        wg-quick up $WG_CONF_FILE
        echo "User $uname removed"
    else
        echo "User not found"
    fi
}

show_status() {
    echo "=== WireGuard Status ==="
    wg show
    echo "=== Interface ==="
    ip a show wg0
}

menu() {
    while true; do
        echo "======================================"
        echo " DarkHole WireGuard UDP Manager"
        echo " Admin password: $ADMIN_PASS"
        echo "======================================"
        echo "1) Add User"
        echo "2) Remove User"
        echo "3) List Users"
        echo "4) Status"
        echo "5) Exit"
        read -p "Choose an option: " opt
        case $opt in
            1) add_user ;;
            2) remove_user ;;
            3) list_users ;;
            4) show_status ;;
            5) exit 0 ;;
            *) echo "Invalid option" ;;
        esac
    done
}

# ----------------------------
# INSTALLATION FLOW
# ----------------------------
install_dependencies
generate_server_keys
generate_server_conf
setup_nat_firewall
create_systemd_service
menu
