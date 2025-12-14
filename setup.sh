#!/bin/bash
# DarkHole WireGuard UDP Installer
# Author: DarkHole Team
# Auto install WireGuard, NAT, and service
# Server UDP port: 5667
# Server internal VPN subnet: 10.66.66.0/24

set -e

WG_CONF_DIR="/etc/darkhole"
WG_SERVER_CONF="$WG_CONF_DIR/wg0.conf"
WG_PORT=5667
WG_SUBNET="10.66.66.0/24"
WG_SERVER_IP="10.66.66.1"
WG_INTERFACE="wg0"

# --- Install dependencies ---
echo "=== Installing dependencies ==="
apt update
apt install -y wireguard qrencode iptables-persistent ufw curl

# --- Create config directory ---
mkdir -p $WG_CONF_DIR
chmod 700 $WG_CONF_DIR

# --- Generate server key pair ---
echo "=== Generating server keys ==="
SERVER_PRIV=$(wg genkey)
SERVER_PUB=$(echo $SERVER_PRIV | wg pubkey)

# --- Create wg0.conf ---
cat > $WG_SERVER_CONF <<EOF
[Interface]
Address = $WG_SERVER_IP/24
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIV
SaveConfig = true
EOF

chmod 600 $WG_SERVER_CONF

# --- Enable IP forwarding ---
echo "=== Enabling IP forwarding ==="
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# --- Setup NAT (iptables + UFW) ---
echo "=== Setting up NAT / firewall ==="
SYS_IF=$(ip -4 route ls | grep default | awk '{print $5}' | head -1)
iptables -t nat -A POSTROUTING -s $WG_SUBNET -o $SYS_IF -j MASQUERADE
iptables-save > /etc/iptables/rules.v4

ufw allow $WG_PORT/udp
ufw enable || true

# --- Create systemd service ---
echo "=== Creating systemd service ==="
cat > /etc/systemd/system/darkhole.service <<EOF
[Unit]
Description=DarkHole WireGuard VPN
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/wg-quick up $WG_INTERFACE
ExecStop=/usr/bin/wg-quick down $WG_INTERFACE
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# --- Enable & start service ---
systemctl daemon-reload
systemctl enable darkhole
systemctl start darkhole

echo "=== DarkHole WireGuard UDP Installation Complete ==="
echo "Server public key: $SERVER_PUB"
echo "Server Listen Port: $WG_PORT"
echo "VPN Subnet: $WG_SUBNET"
echo "Config directory: $WG_CONF_DIR"
echo "Use 'systemctl status darkhole' to check status"
