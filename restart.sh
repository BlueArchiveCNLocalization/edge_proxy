#!/bin/bash

set -e

# Check if run as root
if [ "$EUID" -ne 0 ]; then
  echo "[!] Please run this script with sudo:"
  echo "    sudo $0"
  exit 1
fi
# If port is provided as an argument, update nginx.conf
if [ -n "$1" ]; then
  PORT=$1
  echo "[*] Updating OpenResty to listen on port $PORT..."

  # Update the port in nginx.conf
  sed -i "s/listen [0-9]\+;/listen $PORT;/" /usr/local/openresty/nginx/conf/nginx.conf
  echo "[*] Port updated in nginx.conf"
else
  # Extract the current port from nginx.conf if no port is provided
  PORT=$(grep -oP 'listen \K\d+' /usr/local/openresty/nginx/conf/nginx.conf)
fi

# Restart OpenResty
echo "[*] Restarting OpenResty on port $PORT..."
systemctl restart openresty

echo "[*] OpenResty restarted on port $PORT"
