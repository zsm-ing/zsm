#!/bin/bash

#################################################
# 描述: Alpine 下 sing-box 安装与服务管理脚本
# 版本: 1.1.0
#################################################

CYAN='\033[0;36m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

BIN_PATH="/usr/bin/sing-box"
SERVICE_FILE="/etc/init.d/sing-box"

# 检查是否已安装 sing-box
if command -v sing-box &> /dev/null; then
    echo -e "${CYAN}sing-box 已安装，跳过安装步骤${NC}"
else
    echo "正在下载并安装 sing-box，请稍候..."

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH_NAME="amd64" ;;
        aarch64) ARCH_NAME="arm64" ;;
        armv7l|armv7*) ARCH_NAME="armv7" ;;
        *) echo -e "${RED}不支持的架构: $ARCH${NC}"; exit 1 ;;
    esac

    TMP_DIR="/tmp/singbox_install"
    mkdir -p "$TMP_DIR"
    wget -q -O "$TMP_DIR/sing-box.tar.gz" "https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-$ARCH_NAME.tar.gz"
    tar -xzf "$TMP_DIR/sing-box.tar.gz" -C "$TMP_DIR"
    mv "$TMP_DIR"/sing-box*/sing-box "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -rf "$TMP_DIR"

    if command -v sing-box &> /dev/null; then
        echo -e "${GREEN}sing-box 安装成功${NC}"
    else
        echo -e "${RED}sing-box 安装失败，请检查网络或架构${NC}"
        exit 1
    fi
fi

# 创建 openrc 服务脚本
cat > "$SERVICE_FILE" << 'EOF'
#!/sbin/openrc-run

name="sing-box"
command="/usr/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
pidfile="/run/${RC_SVCNAME}.pid"
command_background="yes"

depend() {
    need net
    use dns logger
}

start_pre() {
    sleep 3
    MODE=$(grep -oE '^MODE=.*' /etc/sing-box/mode.conf | cut -d'=' -f2)
    if [ "$MODE" = "TProxy" ]; then
        /etc/sing-box/scripts/configure_tproxy.sh
    elif [ "$MODE" = "TUN" ]; then
        /etc/sing-box/scripts/configure_tun.sh
    fi
}
EOF

chmod +x "$SERVICE_FILE"

# 启用并启动服务
rc-update add sing-box default
rc-service sing-box start

echo -e "${CYAN}✅ sing-box 服务已启用并启动${NC}"
