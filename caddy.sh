#!/bin/sh
set -eu

### ===== 配置 =====
REPO="zsm-ing/zsm"          # ← 改成你的 GitHub 仓库
SERVICE="caddy"
TMP="/tmp/caddy-update"
### =================

echo "==> Updating Caddy from GitHub Release"

mkdir -p "$TMP"

# 1️⃣ 定位已安装的 Caddy
CADDY_BIN="$(command -v caddy || true)"

if [ -z "$CADDY_BIN" ]; then
  echo "ERROR: Caddy not installed"
  exit 1
fi

echo "Using Caddy binary: $CADDY_BIN"

# 2️⃣ 架构识别
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

# 3️⃣ 当前 / 最新版本
CURRENT="$($CADDY_BIN version 2>/dev/null | awk '{print $1}')"
LATEST=$(wget -qO- https://api.github.com/repos/$REPO/releases/latest \
  | grep '"tag_name"' | head -n1 | cut -d'"' -f4)

[ -n "$LATEST" ] || exit 1

echo "Current: $CURRENT"
echo "Latest:  $LATEST"

[ "$CURRENT" = "$LATEST" ] && exit 0

# 4️⃣ 下载你的 Caddy
NAME="caddy-alpine-$ARCH-$LATEST"
URL="https://github.com/$REPO/releases/download/$LATEST/$NAME"

echo "Downloading $NAME"
wget -q "$URL" -O "$TMP/caddy.new"

# 5️⃣ 严格设置权限（关键）
chown root:root "$TMP/caddy.new"
chmod 755 "$TMP/caddy.new"

# 6️⃣ 停止服务
rc-service "$SERVICE" stop || true

# 7️⃣ 备份并原子替换
cp "$CADDY_BIN" "$TMP/caddy.bak"
cp "$TMP/caddy.new" "$CADDY_BIN"

# 再次确保权限（防止被 umask 影响）
chown root:root "$CADDY_BIN"
chmod 755 "$CADDY_BIN"

# 8️⃣ 启动并验证
rc-service "$SERVICE" start || true
sleep 2

if "$CADDY_BIN" version >/dev/null 2>&1; then
  echo "✔ Caddy updated successfully to $LATEST"
  rm -rf "$TMP"
  exit 0
fi

# 9️⃣ 回滚（安全兜底）
echo "✖ Update failed, rolling back"
cp "$TMP/caddy.bak" "$CADDY_BIN"
chown root:root "$CADDY_BIN"
chmod 755 "$CADDY_BIN"
rc-service "$SERVICE" start || true
exit 1
