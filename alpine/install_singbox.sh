#!/bin/bash
#################################################
# 描述: Alpine 下 sing-box 安装与服务管理脚本
# 版本: 2.0.0
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

    # 下载最新版本的 tar 包
    DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-$ARCH_NAME.tar.gz"
    wget -q -O "$TMP_DIR/sing-box.tar.gz" "$DOWNLOAD_URL"

    if [ ! -s "$TMP_DIR/sing-box.tar.gz" ]; then
        echo -e "${RED}下载失败，请检查网络或代理${NC}"
        exit 1
    fi

    # 解压缩
    tar -xzf "$TMP_DIR/sing-box.tar.gz" -C "$TMP_DIR" || { echo -e "${RED}解压失败${NC}"; exit 1; }

    # 查找二进制文件
    bin_file=$(find "$TMP_DIR" -type f -name sing-box | head -n1)
    if [ -z "$bin_file" ]; then
        echo -e "${RED}未找到 sing-box 可执行文件，请检查下载包${NC}"
        exit 1
    fi

    mv "$bin_file" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -rf "$TMP_DIR"

    if command -v sing-box &> /dev/null; then
        echo -e "${GREEN}sing-box 安装成功${NC}"
    else
        echo -e "${RED}sing-box 安装失败，请检查日志或架构${NC}"
        exit 1
    fi
fi

# 确保配置文件存在
mkdir -p /etc/sing-box
if [ ! -f /etc/sing-box/config.json ]; then
    cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [],
  "outbounds": []
}
EOF
    echo -e "${CYAN}已生成最小化配置文件 /etc/sing-box/config.json${NC}"
fi

# 确保模式文件存在
if [ ! -f /etc/sing-box/mode.conf ]; then
    echo "MODE=TProxy" > /etc/sing-box/mode.conf
    echo -e "${CYAN}已生成默认模式文件 /etc/sing-box/mode.conf${NC}"
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
        [ -x /etc/sing-box/scripts/configure_tproxy.sh ] && /etc/sing-box/scripts/configure_tproxy.sh
    elif [ "$MODE" = "TUN" ]; then
        [ -x /etc/sing-box/scripts/configure_tun.sh ] && /etc/sing-box/scripts/configure_tun.sh
    fi
}
EOF

chmod +x "$SERVICE_FILE"

# 启用并启动服务
rc-update add sing-box default
rc-service sing-box restart

echo -e "${CYAN}✅ sing-box 服务已启用并启动${NC}"
