#!/bin/bash
set -Eeuo pipefail

# ===== 仅允许 Alpine Linux =====
if [ ! -f /etc/os-release ] || ! grep -qi '^ID=alpine' /etc/os-release; then
    echo -e "\033[0;31m[ERROR]\033[0m 本脚本仅支持 Alpine Linux"
    exit 1
fi

# ===== 颜色 =====
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# ===== 配置文件路径 =====
CONFIG_FILE="/etc/sing-box/config.json"

# ===== 检查 sing-box 是否存在 =====
if ! command -v sing-box >/dev/null 2>&1; then
    echo -e "${RED}未找到 sing-box，请先安装${NC}"
    exit 1
fi

# ===== 检查配置文件 =====
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${CYAN}检查配置文件 ${CONFIG_FILE} ...${NC}"

    if sing-box check -c "$CONFIG_FILE"; then
        echo -e "${CYAN}配置文件验证通过！${NC}"
    else
        echo -e "${RED}配置文件验证失败！${NC}"
        exit 1
    fi
else
    echo -e "${RED}配置文件 ${CONFIG_FILE} 不存在！${NC}"
    exit 1
fi
