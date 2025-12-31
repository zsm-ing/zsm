#!/bin/bash
set -Eeuo pipefail

# ===== Alpine 系统检测 =====
if [ ! -f /etc/os-release ] || ! grep -qi '^ID=alpine' /etc/os-release; then
    echo -e "\033[0;31m[ERROR]\033[0m 本脚本仅支持 Alpine Linux"
    exit 1
fi

# ===== 颜色 =====
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ===== 功能函数 =====
view_firewall_rules() {
    echo -e "${YELLOW}查看防火墙规则...${NC}"
    if command -v nft >/dev/null 2>&1; then
        nft list ruleset
    else
        echo -e "${RED}未安装 nftables 或命令不可用${NC}"
    fi
    read -rp "按回车键返回二级菜单..."
}

check_config() {
    echo -e "${YELLOW}检查配置文件...${NC}"
    if [ -f /etc/sing-box/scripts/check_config.sh ]; then
        bash /etc/sing-box/scripts/check_config.sh
    else
        echo -e "${RED}未找到 check_config.sh 脚本${NC}"
    fi
    read -rp "按回车键返回二级菜单..."
}

view_logs() {
    echo -e "${YELLOW}日志生成中，请等待...${NC}"
    echo -e "${RED}按 Ctrl + C 结束日志输出${NC}"
    # Alpine 下读取系统日志
    if command -v journalctl >/dev/null 2>&1; then
        journalctl -f -u sing-box
    else
        echo -e "${RED}未找到 journalctl，无法实时查看日志${NC}"
    fi
    read -rp "按回车键返回二级菜单..."
}

# ===== 菜单显示 =====
show_submenu() {
    echo -e "${CYAN}=========== 二级菜单选项 ===========${NC}"
    echo -e "${MAGENTA}1. 查看防火墙规则${NC}"
    echo -e "${MAGENTA}2. 检查配置文件${NC}"
    echo -e "${MAGENTA}3. 查看实时日志${NC}"
    echo -e "${MAGENTA}0. 返回主菜单${NC}"
    echo -e "${CYAN}===================================${NC}"
}

handle_submenu_choice() {
    while true; do
        read -rp "请选择操作: " choice
        case $choice in
            1) view_firewall_rules ;;
            2) check_config ;;
            3) view_logs ;;
            0) return 0 ;;
            *) echo -e "${RED}无效的选择${NC}" ;;
        esac
        show_submenu
    done
}

# ===== 主循环 =====
menu_active=true
while $menu_active; do
    show_submenu
    handle_submenu_choice
    [[ $? -eq 0 ]] && menu_active=false
done
