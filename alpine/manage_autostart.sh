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
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}设置 sing-box 开机自启动${NC}"
echo "请选择操作(1: 启用自启动, 2: 禁用自启动)"
read -rp "(1/2): " autostart_choice

# ===== 防火墙应用函数 =====
apply_firewall() {
    if [ ! -f /etc/sing-box/mode.conf ]; then
        echo -e "${RED}未找到 /etc/sing-box/mode.conf，无法应用防火墙规则${NC}"
        return 1
    fi

    MODE=$(grep -oP '(?<=^MODE=).*' /etc/sing-box/mode.conf)

    case "$MODE" in
        TProxy)
            echo -e "${GREEN}应用 TProxy 模式防火墙规则...${NC}"
            bash /etc/sing-box/scripts/configure_tproxy.sh
            ;;
        TUN)
            echo -e "${GREEN}应用 TUN 模式防火墙规则...${NC}"
            bash /etc/sing-box/scripts/configure_tun.sh
            ;;
        *)
            echo -e "${RED}无效的模式：$MODE，跳过防火墙规则应用${NC}"
            return 1
            ;;
    esac
}

# ===== 主操作 =====
case "$autostart_choice" in
    1)
        echo -e "${GREEN}启用自启动...${NC}"
        rc-update add sing-box default
        rc-service sing-box start || { echo -e "${RED}启动服务失败${NC}"; exit 1; }
        echo -e "${GREEN}自启动已成功启用并启动服务${NC}"
        ;;
    2)
        echo -e "${RED}禁用自启动...${NC}"
        rc-service sing-box stop || echo -e "${RED}停止服务失败或服务未运行${NC}"
        rc-update del sing-box default
        echo -e "${GREEN}自启动已成功禁用${NC}"
        ;;
    *)
        echo -e "${RED}无效选择，请输入 1 或 2${NC}"
        exit 1
        ;;
esac

# ===== 可选：自动应用防火墙 =====
if [ "${1:-}" = "apply_firewall" ]; then
    apply_firewall
fi
