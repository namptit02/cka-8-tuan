#!/usr/bin/env bash
# Cài web terminal (ttyd) trên VM lab để nhúng vào trang ôn CKA.
# Dùng:  bash setup-web-terminal.sh [IP_CUA_VM] [PORT]
#   Mặc định IP = IP đầu tiên của máy, PORT = 7681
#   Tuỳ chọn bật mật khẩu:  TTYD_PASS='mat-khau' bash setup-web-terminal.sh
set -euo pipefail

IP="${1:-$(hostname -I | awk '{print $1}')}"
PORT="${2:-7681}"
RUN_USER="$(id -un)"
HOME_DIR="$(getent passwd "$RUN_USER" | cut -d: -f6)"
CERT_DIR="$HOME_DIR/.ttyd"

echo "==> VM IP: $IP  port: $PORT  user: $RUN_USER"

# 0. Đồng bộ đồng hồ (VM bị suspend hay lệch giờ -> apt báo "Release file ... is not valid yet")
sudo timedatectl set-ntp true 2>/dev/null || true
NET_DATE="$(curl -sI --max-time 10 http://www.google.com | awk -F': ' 'tolower($1)=="date"{print $2}' | tr -d '\r')"
if [ -n "$NET_DATE" ]; then
  DRIFT=$(( $(date -u +%s) - $(date -u -d "$NET_DATE" +%s) ))
  if [ "${DRIFT#-}" -gt 120 ]; then
    echo "==> Đồng hồ VM lệch ${DRIFT}s, chỉnh theo giờ mạng: $NET_DATE"
    sudo date -u -s "$NET_DATE" >/dev/null
  fi
fi

# 1. Cài ttyd (apt; nếu không có thì tải binary chính thức)
if ! command -v ttyd >/dev/null 2>&1; then
  sudo apt-get update -y || echo "!! apt-get update có lỗi, vẫn thử cài tiếp"
  if ! sudo apt-get install -y ttyd; then
    ARCH="$(uname -m)"            # x86_64 | aarch64
    sudo curl -fL -o /usr/local/bin/ttyd "https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.${ARCH}"
    sudo chmod +x /usr/local/bin/ttyd
  fi
fi
command -v openssl >/dev/null || sudo apt-get install -y openssl
TTYD_BIN="$(command -v ttyd)"
"$TTYD_BIN" --version

# 2. Chứng chỉ tự ký có SAN là IP của VM (trang Vercel chạy HTTPS nên terminal cũng phải HTTPS)
mkdir -p "$CERT_DIR" && chmod 700 "$CERT_DIR"
if [ ! -f "$CERT_DIR/cert.pem" ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
    -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" \
    -subj "/CN=$IP" -addext "subjectAltName=IP:$IP,DNS:localhost"
fi
chmod 600 "$CERT_DIR/key.pem"

# 3. Chỉ lắng nghe trên card mạng có IP này
IFACE="$(ip -o -4 addr show | awk -v ip="$IP" '{split($4,a,"/"); if (a[1]==ip) print $2}' | head -1)"
IFACE_OPT=""
[ -n "$IFACE" ] && IFACE_OPT="-i $IFACE"

# 4. Mật khẩu (tuỳ chọn)
sudo install -m 600 /dev/null /etc/ttyd.env
AUTH_OPT=""
if [ -n "${TTYD_PASS:-}" ]; then
  echo "TTYD_CRED=$RUN_USER:$TTYD_PASS" | sudo tee /etc/ttyd.env >/dev/null
  AUTH_OPT='-c ${TTYD_CRED}'
fi

# 5. Service systemd
sudo tee /etc/systemd/system/ttyd.service >/dev/null <<UNIT
[Unit]
Description=Web terminal (ttyd) cho lab CKA
After=network-online.target
Wants=network-online.target

[Service]
User=$RUN_USER
WorkingDirectory=$HOME_DIR
EnvironmentFile=/etc/ttyd.env
ExecStart=$TTYD_BIN -W -O $IFACE_OPT -p $PORT -S -C $CERT_DIR/cert.pem -K $CERT_DIR/key.pem $AUTH_OPT -t fontSize=15 -t titleFixed=CKA-lab /bin/bash -l
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now ttyd
sleep 1
sudo systemctl --no-pager --lines=5 status ttyd || true

# 6. Mở firewall nếu đang bật ufw
if command -v ufw >/dev/null && sudo ufw status | grep -q "Status: active"; then
  sudo ufw allow "$PORT/tcp"
fi

echo
echo "==> Xong. Mở https://$IP:$PORT trong trình duyệt MỘT LẦN, chấp nhận chứng chỉ tự ký,"
echo "    rồi vào trang ôn thi, mở Terminal / Phòng thi, nhập https://$IP:$PORT và bấm Kết nối."
echo "    Gỡ:  sudo systemctl disable --now ttyd && sudo rm /etc/systemd/system/ttyd.service"
