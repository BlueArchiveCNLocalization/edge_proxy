#!/bin/bash
set -e

# Check if the script is run as root
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

# Detect OS and codename
. /etc/os-release
OS_ID=$ID
OS_CODENAME=${VERSION_CODENAME:-$(lsb_release -sc 2>/dev/null || echo "")}

echo "[*] Detected OS: $OS_ID ($OS_CODENAME)"

# Install OpenResty based on the distribution
install_openresty() {
  case "$OS_ID" in
    ubuntu|debian)
      echo "[*] Installing dependencies..."
      apt update
      apt install -y curl gnupg2 ca-certificates lsb-release unzip git software-properties-common

      echo "[*] Adding OpenResty repo for $OS_ID ($OS_CODENAME)..."
      wget -qO - https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/openresty.gpg

      # For Debian
      if [[ "$OS_ID" == "debian" ]]; then
        echo "deb [signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/debian bullseye openresty" \
          > /etc/apt/sources.list.d/openresty.list
      # For Ubuntu
      elif [[ "$OS_ID" == "ubuntu" ]]; then
        echo "deb [signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/ubuntu $OS_CODENAME main" \
          > /etc/apt/sources.list.d/openresty.list
      fi

      apt update
      apt install -y openresty luarocks
      ;;
    
    centos|rhel|rocky|almalinux)
      echo "[*] Installing dependencies..."
      yum install -y yum-utils curl unzip git

      echo "[*] Adding OpenResty repo for $OS_ID..."
      yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo

      yum install -y openresty luarocks
      ;;

    fedora)
      echo "[*] Installing dependencies..."
      dnf install -y dnf-plugins-core curl unzip git

      echo "[*] Adding OpenResty repo for Fedora..."
      dnf config-manager --add-repo https://openresty.org/package/fedora/openresty.repo

      dnf install -y openresty luarocks
      ;;

    *)
      echo "[!] Unsupported OS: $OS_ID"
      exit 1
      ;;
  esac
}

echo "[*] Installing OpenResty and LuaRocks..."
install_openresty

echo "[*] Installing lua-resty-rsa..."
luarocks install lua-resty-rsa

echo "[*] Creating proxy cache directory..."
mkdir -p /usr/local/openresty/nginx/proxy-cache
chown -R www-data:www-data /usr/local/openresty/nginx/proxy-cache 2>/dev/null || chown -R nginx:nginx /usr/local/openresty/nginx/proxy-cache
chmod -R 755 /usr/local/openresty/nginx/proxy-cache

echo "[*] Copying nginx config..."
cp ./nginx/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

echo "[*] Injecting port $PORT into config..."
sed -i "s/listen 80;/listen $PORT;/" /usr/local/openresty/nginx/conf/nginx.conf

echo "[*] Copying Lua and key files..."
mkdir -p /usr/local/openresty/nginx/lua
mkdir -p /usr/local/openresty/nginx/keys
cp ./nginx/lua/verify.lua /usr/local/openresty/nginx/lua/
cp ./nginx/keys/public.pem /usr/local/openresty/nginx/keys/

echo "[*] Restarting OpenResty..."
systemctl restart openresty || service openresty restart

echo "[*] Configuring firewall for port $PORT..."

# If UFW is installed, allow the port
if command -v ufw >/dev/null; then
    ufw allow "$PORT/tcp"
# If firewalld is installed, allow the port
elif command -v firewall-cmd >/dev/null; then
    firewall-cmd --permanent --add-port="$PORT"/tcp
    firewall-cmd --reload
# If iptables is installed, add a rule for the port
elif command -v iptables >/dev/null; then
    iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
fi

# Get public IP
IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip)

echo
echo "======================================="
echo "[+] Setup complete!"
echo "[*] Proxy server is live at: http://$IP:$PORT"
echo "======================================="
