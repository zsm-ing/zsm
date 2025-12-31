#!/bin/bash
set -Eeuo pipefail

# ===== Alpine 系统检测 =====
if [ ! -f /etc/os-release ] || ! grep -qi '^ID=alpine' /etc/os-release; then
    echo -e "\033[0;31m[ERROR]\033[0m 本脚本仅支持 Alpine Linux"
    exit 1
fi

# ===== root 检查 =====
if [ "$(id -u)" != "0" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m 此脚本需要 root 权限"
    exit 1
fi

# ===== 颜色 =====
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# ===== 安装 sing-box =====
if command -v sing-box >/dev/null 2>&1; then
    echo -e "${CYAN}sing-box 已安装，跳过安装步骤${NC}"
else
    echo -e "${CYAN}正在更新包列表并安装 sing-box，请稍候...${NC}"
    apk update >/dev/null 2>&1
    apk add kmod-nft-tproxy >/dev/null 2>&1
    apk add sing-box >/dev/null 2>&1

    if command -v sing-box >/dev/null 2>&1; then
        echo -e "${CYAN}sing-box 安装成功${NC}"
    else
        echo -e "${RED}sing-box 安装失败，请检查日志或网络配置${NC}"
        exit 1
    fi
fi

# ===== 配置 OpenRC 服务 =====
INIT_SCRIPT="/etc/init.d/sing-box"

# 删除旧服务定义
if [ -f "$INIT_SCRIPT" ]; then
    sed -i '/start_service()/,/}/d' "$INIT_SCRIPT"
    sed -i '/stop_service()/,/}/d' "$INIT_SCRIPT"
fi

cat << 'EOF' >> "$INIT_SCRIPT"
#!/sbin/openrc-run

command=/usr/bin/sing-box
command_args="run -c /etc/sing-box/config.json"
name=sing-box
description="Sing-box proxy service"

start_service() {
    procd_open_instance
    procd_set_param command $command $command_args
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance

    # 等待服务启动
    sleep 3

    # 根据模式应用防火墙规则
    if [ -f /etc/sing-box/mode.conf ]; then
        MODE=$(grep -oE '^MODE=.*' /etc/sing-box/mode.conf | cut -d'=' -f2)
        if [ "$MODE" = "TProxy" ]; then
            /etc/sing-box/scripts/configure_tproxy.sh
        elif [ "$MODE" = "TUN" ]; then
            /etc/sing-box/scripts/configure_tun.sh
        fi
    fi
}

stop_service() {
    procd_kill "$NAME" 2>/dev/null || true
}
EOF

chmod +x "$INIT_SCRIPT"

# ===== 启用并启动服务 =====
rc-update add sing-box default
rc-service sing-box start

echo -e "${CYAN}sing-box 服务已启用并启动${NC}"
