#!/usr/bin/env python3
import os, json, subprocess, time

DARKHOLE_DIR="/usr/local/darkhole"
USERS_FILE=f"{DARKHOLE_DIR}/users.json"

def log(msg):
    timestamp = time.strftime("[%Y-%m-%d %H:%M:%S]")
    print(f"{timestamp} {msg}")

def load_users():
    if not os.path.exists(USERS_FILE):
        return []
    with open(USERS_FILE,"r") as f:
        return json.load(f)

def server_status():
    try:
        # Cek service
        result = subprocess.run(["systemctl","is-active","darkhole"], capture_output=True, text=True)
        status_service = result.stdout.strip()
        
        # Cek NAT / firewall
        nat_status = subprocess.run(["iptables","-t","nat","-L","POSTROUTING"], capture_output=True, text=True)
        nat_active = "Active" if "MASQUERADE" in nat_status.stdout else "Inactive"
        
        # Cek UDP port
        udp_status = subprocess.run(["ss","-lunp"], capture_output=True, text=True)
        udp_info = [line for line in udp_status.stdout.splitlines() if "5667" in line]
        udp_display = udp_info[0] if udp_info else "Port 5667 not listening"

        # Total user
        users = load_users()
        total_user = len(users)

        print("="*60)
        print(" DarkHole UDP VPN - Status Overview (Auto Refresh, Ctrl+C to exit)")
        print("="*60)
        print(f"Service Status    : {status_service}")
        print(f"NAT / Firewall    : {nat_active}")
        print(f"UDP Interface     : {udp_display}")
        print(f"Total Users       : {total_user}")
        print("="*60)
    except Exception as e:
        log(f"Error retrieving status: {e}")

def add_user():
    username = input("Enter username: ").strip()
    password = input("Enter password: ").strip()
    users = load_users()
    ips = [u["ip"] for u in users]
    next_ip = "10.66.66.2"
    while next_ip in ips:
        last = int(next_ip.split(".")[3])
        next_ip = f"10.66.66.{last+1}"
    new_user = {"username":username,"password":password,"ip":next_ip}
    users.append(new_user)
    with open(USERS_FILE,"w") as f:
        json.dump(users,f,indent=2)
    cfg_file = os.path.join(DARKHOLE_DIR,f"{username}.conf")
    with open(cfg_file,"w") as f:
        f.write(f"server_ip=SERVER_IP\n")
        f.write(f"server_port=5667\n")
        f.write(f"username={username}\n")
        f.write(f"password={password}\n")
    log(f"[OK] User {username} added with IP {next_ip}")

def remove_user():
    username=input("Enter username to remove: ").strip()
    users=load_users()
    users=[u for u in users if u["username"]!=username]
    with open(USERS_FILE,"w") as f:
        json.dump(users,f,indent=2)
    cfg_file = os.path.join(DARKHOLE_DIR,f"{username}.conf")
    if os.path.exists(cfg_file):
        os.remove(cfg_file)
    log(f"[OK] User {username} removed")

def list_users():
    users=load_users()
    if not users:
        log("No users")
        return
    for u in users:
        log(f"{u['username']} | {u['password']} | {u['ip']}")

def start_server():
    subprocess.run(["systemctl","start","darkhole"])

def stop_server():
    subprocess.run(["systemctl","stop","darkhole"])

def restart_server():
    subprocess.run(["systemctl","restart","darkhole"])

def status_menu():
    try:
        while True:
            os.system("clear")
            server_status()
            time.sleep(3)
    except KeyboardInterrupt:
        print("\nExiting status view...")

def menu():
    while True:
        print("="*50)
        print(" DarkHole UDP VPN Manager - Production")
        print("="*50)
        print("1) Add User")
        print("2) Remove User")
        print("3) List Users")
        print("4) Status Overview (Auto Refresh)")
        print("5) Start VPN Service")
        print("6) Stop VPN Service")
        print("7) Restart VPN Service")
        print("8) Exit")
        choice=input("Choose an option: ").strip()
        if choice=="1":
            add_user()
        elif choice=="2":
            remove_user()
        elif choice=="3":
            list_users()
        elif choice=="4":
            status_menu()
        elif choice=="5":
            start_server()
        elif choice=="6":
            stop_server()
        elif choice=="7":
            restart_server()
        elif choice=="8":
            exit()
        else:
            log("Invalid choice!")

if __name__=="__main__":
    menu()
