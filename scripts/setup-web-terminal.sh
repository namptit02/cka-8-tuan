#!/usr/bin/env bash
# Cài web terminal (ttyd) trên VM lab để nhúng vào trang ôn CKA.
# Dùng:  bash setup-web-terminal.sh [IP_CUA_VM] [PORT]
#   Mặc định IP = IP đầu tiên của máy, PORT = 7681
#   Tuỳ chọn bật mật khẩu:  TTYD_PASS='mat-khau' bash setup-web-terminal.sh
#   Tự chạy khi VM khởi động: START_ON_BOOT=1 bash setup-web-terminal.sh  (mặc định: KHÔNG)
#   Máy được phép kết nối:     ALLOW_FROM=192.168.64.1 (mặc định: gateway = máy Mac chủ)
#
# Bảo mật:
#  - Chỉ nghe trên card mạng của IP VM, không nghe 0.0.0.0.
#  - Tường lửa chỉ cho máy chủ (Mac) vào cổng terminal, các máy/VM khác bị DROP.
#  - Kiểm tra Origin của websocket (-O): trang web lạ không mở được phiên shell.
#  - Không tự chạy khi khởi động; bật/tắt bằng lệnh term-on / term-off.
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

# 5. Chỉ cho máy chủ (Mac) truy cập cổng terminal
ALLOW_FROM="${ALLOW_FROM:-$(ip route show default | awk '{print $3; exit}')}"
[ -n "$ALLOW_FROM" ] || { echo "!! Không xác định được IP máy chủ, đặt ALLOW_FROM=..."; exit 1; }
command -v iptables >/dev/null || sudo apt-get install -y iptables
IPT="$(command -v iptables)"
FW_RULE="INPUT -p tcp --dport $PORT ! -s $ALLOW_FROM -m comment --comment cka-ttyd -j DROP"
echo "==> Chỉ cho phép $ALLOW_FROM kết nối tới cổng $PORT"

# 6. Service systemd
sudo tee /etc/systemd/system/ttyd.service >/dev/null <<UNIT
[Unit]
Description=Web terminal (ttyd) cho lab CKA
After=network-online.target
Wants=network-online.target

[Service]
User=$RUN_USER
WorkingDirectory=$HOME_DIR
EnvironmentFile=/etc/ttyd.env
ExecStartPre=+/bin/sh -c '$IPT -C $FW_RULE 2>/dev/null || $IPT -I $FW_RULE'
ExecStart=$TTYD_BIN -W -O $IFACE_OPT -p $PORT -S -C $CERT_DIR/cert.pem -K $CERT_DIR/key.pem $AUTH_OPT -t fontSize=15 -t titleFixed=CKA-lab /bin/bash -l
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
if [ "${START_ON_BOOT:-0}" = "1" ]; then sudo systemctl enable ttyd; else sudo systemctl disable ttyd 2>/dev/null || true; fi
sudo systemctl restart ttyd   # restart: thay cấu hình mặc định của gói apt (chỉ nghe trên lo)
sleep 1
sudo systemctl --no-pager --lines=5 status ttyd || true

# 7. Nếu ufw đang bật: chỉ mở cổng cho máy chủ
if command -v ufw >/dev/null && sudo ufw status | grep -q "Status: active"; then
  sudo ufw delete allow "$PORT/tcp" >/dev/null 2>&1 || true
  sudo ufw allow from "$ALLOW_FROM" to any port "$PORT" proto tcp
fi

# 8. Lệnh tắt/bật nhanh
if ! grep -q "# cka-ttyd aliases" "$HOME_DIR/.bashrc" 2>/dev/null; then
  cat >> "$HOME_DIR/.bashrc" <<'ALIAS'
# cka-ttyd aliases
alias term-on='sudo systemctl start ttyd && echo "web terminal: BAT"'
alias term-off='sudo systemctl stop ttyd && echo "web terminal: TAT"'
alias term-status='systemctl is-active ttyd; sudo ss -tnp | grep -c ":7681 " | xargs echo "ket noi dang mo:"'
ALIAS
fi

echo
echo "==> Xong. Mở https://$IP:$PORT trong trình duyệt MỘT LẦN, chấp nhận chứng chỉ tự ký,"
echo "    rồi vào trang ôn thi, mở Terminal / Phòng thi, nhập https://$IP:$PORT và bấm Kết nối."
echo "    Bật/tắt: term-on / term-off  (mở shell mới hoặc: source ~/.bashrc)"
echo "    Gỡ hẳn:  sudo systemctl disable --now ttyd && sudo rm /etc/systemd/system/ttyd.service && sudo $IPT -D $FW_RULE"
