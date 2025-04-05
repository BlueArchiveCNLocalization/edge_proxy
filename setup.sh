#!/bin/bash

set -e

# Check if run as root
if [ "$EUID" -ne 0 ]; then
  echo "[!] Please run this script with sudo:"
  echo "    sudo $0 <port>"
  exit 1
fi

PORT=$1

if [ -z "$PORT" ]; then
  echo "Usage: sudo $0 <port>"
  exit 1
fi

echo "[*] Installing OpenResty and dependencies..."

# Install dependencies
apt update
apt install -y curl gnupg2 ca-certificates lsb-release unzip git software-properties-common

# Add OpenResty repository and install OpenResty
wget -qO - https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/openresty.gpg
echo "deb [signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/ubuntu $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/openresty.list
apt update
apt install -y openresty

echo "[*] Installing LuaRocks (Lua package manager)..."
apt install -y luarocks

# Install lua-resty-rsa using LuaRocks
echo "[*] Installing lua-resty-rsa..."
luarocks install lua-resty-rsa

echo "[*] Creating cache directory..."
mkdir -p /usr/local/openresty/nginx/proxy-cache

echo "[*] Copying nginx config..."
cp ./nginx/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

echo "[*] Injecting port $PORT into config..."
sed -i "s/listen 80;/listen $PORT;/" /usr/local/openresty/nginx/conf/nginx.conf

echo "[*] Copying Lua scripts..."
mkdir -p /usr/local/openresty/nginx/lua
cp ./nginx/lua/verify.lua /usr/local/openresty/nginx/lua/

echo "[*] Setting up public key..."
mkdir -p /usr/local/openresty/nginx/keys
cp ./nginx/keys/public.pem /usr/local/openresty/nginx/keys/

echo "[*] Restarting OpenResty..."
systemctl restart openresty

echo "[*] Configuring firewall to allow traffic on port $PORT..."

# If UFW is installed, allow port 80/tcp
if command -v ufw >/dev/null; then
    echo "[*] UFW detected. Allowing port $PORT/tcp..."
    ufw allow "$PORT/tcp"
fi

# Insert iptables rule to allow incoming traffic on the specified port
echo "[*] Inserting iptables rule to accept TCP traffic on port $PORT..."
iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT

# Get public IP
IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip)

echo
echo "======================================="
echo "[+] Setup complete!"
echo "[*] Proxy server is live at: http://$IP:$PORT"
echo "======================================="
