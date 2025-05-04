#!/bin/bash
set -e

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "[!] Please run this script with sudo:"
  echo "    sudo $0 <port> [--china]"
  exit 1
fi

PORT=$1
CHINA_FLAG=$2

if [ -z "$PORT" ]; then
  echo "Usage: sudo $0 <port> [--china]"
  exit 1
fi

# Detect OS and codename
. /etc/os-release
OS_ID=$ID
OS_CODENAME=${VERSION_CODENAME:-$(lsb_release -sc 2>/dev/null || echo "")}

echo "[*] Detected OS: $OS_ID ($OS_CODENAME)"

install_openresty() {
  case "$OS_ID" in
    ubuntu|debian)
      echo "[*] Installing dependencies..."
      apt update
      apt install -y curl wget gnupg2 ca-certificates lsb-release unzip git software-properties-common

      # get public IP
      PUBLIC_IP=$(curl -s ifconfig.me)

      echo "[*] Importing OpenResty GPG key..."
      if [ "$CHINA_FLAG" == "--china" ]; then
        echo "    — China option detected: using USTC mirror key"
        wget -qO - https://mirrors.ustc.edu.cn/openresty/pubkey.gpg \
          | gpg --dearmor -o /usr/share/keyrings/openresty.gpg
      else
        echo "    — non-China: using official key"
        wget -qO - https://openresty.org/package/pubkey.gpg \
          | gpg --dearmor -o /usr/share/keyrings/openresty.gpg
      fi

      echo "[*] Adding OpenResty repo..."
      if [ "$CHINA_FLAG" == "--china" ]; then
        # USTC mirror
        if [[ "$OS_ID" == "debian" ]]; then
          repo="https://mirrors.ustc.edu.cn/openresty/debian bullseye openresty"
        else
          repo="https://mirrors.ustc.edu.cn/openresty/ubuntu $OS_CODENAME main"
        fi
      else
        # official
        if [[ "$OS_ID" == "debian" ]]; then
          repo="http://openresty.org/package/debian bullseye openresty"
        else
          repo="http://openresty.org/package/ubuntu $OS_CODENAME main"
        fi
      fi
      echo "deb [signed-by=/usr/share/keyrings/openresty.gpg] $repo" \
        > /etc/apt/sources.list.d/openresty.list

      apt update
      apt install -y openresty luarocks
      ;;

    centos|rhel|rocky|almalinux)
      echo "[*] Installing dependencies..."
      yum install -y yum-utils curl wget unzip git

      PUBLIC_IP=$(curl -s ifconfig.me)

      echo "[*] Adding OpenResty repo..."
      if [ "$CHINA_FLAG" == "--china" ]; then
        echo "    — China option detected: using USTC mirror"
        repo="https://mirrors.ustc.edu.cn/openresty/centos/openresty.repo"
      else
        echo "    — non-China: using official"
        repo="https://openresty.org/package/centos/openresty.repo"
      fi
      yum-config-manager --add-repo "$repo"

      yum install -y openresty luarocks
      ;;

    fedora)
      echo "[*] Installing dependencies..."
      dnf install -y dnf-plugins-core curl wget unzip git

      PUBLIC_IP=$(curl -s ifconfig.me)

      echo "[*] Adding OpenResty repo..."
      if [ "$CHINA_FLAG" == "--china" ]; then
        echo "    — China option detected: using USTC mirror"
        repo="https://mirrors.ustc.edu.cn/openresty/fedora/openresty.repo"
      else
        echo "    — non-China: using official"
        repo="https://openresty.org/package/fedora/openresty.repo"
      fi
      dnf config-manager --add-repo "$repo"

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

echo "[*] Installing lua-resty-http..."
luarocks install lua-resty-http

echo "[*] Creating proxy cache directory..."
mkdir -p /usr/local/openresty/nginx/proxy-cache
chown -R www-data:www-data /usr/local/openresty/nginx/proxy-cache 2>/dev/null || chown -R nginx:nginx /usr/local/openresty/nginx/proxy-cache
chmod -R 755 /usr/local/openresty/nginx/proxy-cache

echo "[*] Copying nginx config..."
cp ./nginx/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

echo "[*] Injecting port $PORT into config..."
sed -i "s/listen 80;/listen $PORT;/" /usr/local/openresty/nginx/conf/nginx.conf
sed -i "s/listen \[::\]:80;/listen [::]:$PORT;/" /usr/local/openresty/nginx/conf/nginx.conf

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
    firewall-cmd --permanent --add-rich-rule="rule family='ipv6' port port='$PORT' protocol='tcp' accept"
    firewall-cmd --reload
# If iptables is installed, add a rule for the port
else
  if command -v iptables >/dev/null; then
    while iptables -D INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; do :; done
    iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
  fi
  if command -v ip6tables >/dev/null; then
    while ip6tables -D INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; do :; done
    ip6tables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
  fi
fi

# Get public IP
IPV4=$(curl -s -4 ifconfig.me || curl -s -6 ipinfo.io/ip)
IPV6=$(curl -s -6 ifconfig.me || curl -s -6 v6.ipinfo.io/ip)
IPV4=${IPV4:-"IPv4 Unavailable"}
IPV6=${IPV6:-"IPv6 Unavailable"}

echo
echo "======================================="
echo "[+] Setup complete!"
echo "[*] Proxy server is live at:"
echo "[*] IPv4: http://$IPV4:$PORT"
echo "[*] IPv6: http://[$IPV6]:$PORT"
echo "======================================="
