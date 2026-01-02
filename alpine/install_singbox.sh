#!/bin/bash

#################################################
# 描述: Alpine 下 sing-box 安装与服务管理脚本
# 版本: 1.0.0
#################################################

# 定义颜色
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 检查是否已安装 sing-box
if command -v sing-box &> /dev/null; then
    echo -e "${CYAN}sing-box 已安装，跳过安装步骤${NC}"
else
    echo "正在更新包列表并安装 sing-box，请稍候..."
    apk update >/dev/null 2>&1
    apk add sing-box nftables >/dev/null 2>&1

    if command -v sing-box &> /dev/null; then
        echo -e "${CYAN}sing-box 安装成功${NC}"
    else
        echo -e "${RED}sing-box 安装失败，请检查日志或网络配置${NC}"
        exit 1
    fi
fi

# 创建 openrc 服务脚本
SERVICE_FILE="/etc/init.d/sing-box"

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
    # 等待服务完全启动
    sleep 3

    # 读取模式并应用防火墙规则
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

echo -e "${CYAN}sing-box 服务已启用并启动${NC}"
