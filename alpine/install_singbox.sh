#!/bin/bash
#################################################
# 描述: Alpine 下 sing-box 安装与服务管理脚本（使用 edge 仓库源）
# 版本: 2.2.0
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
    echo "正在更新包列表并安装 sing-box，请稍候..."

    # 使用 edge/community 仓库源安装
    apk update \
      --repository=http://dl-cdn.alpinelinux.org/alpine/edge/main \
      --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community

    apk add sing-box nftables

    if command -v sing-box &> /dev/null; then
        echo -e "${GREEN}sing-box 安装成功${NC}"
    else
        echo -e "${RED}sing-box 安装失败，请检查仓库源或网络${NC}"
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
