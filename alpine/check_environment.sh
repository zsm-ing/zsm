#!/bin/bash
set -Eeuo pipefail

# ===== 仅允许 Alpine Linux =====
if [ ! -f /etc/os-release ] || ! grep -qi '^ID=alpine' /etc/os-release; then
    echo -e "\033[0;31m[ERROR]\033[0m 本脚本仅支持 Alpine Linux"
    exit 1
fi

# ===== 检查 root 权限 =====
if [ "$(id -u)" != "0" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m 此脚本需要 root 权限"
    exit 1
fi

# ===== 检查 sing-box =====
if command -v sing-box >/dev/null 2>&1; then
    current_version=$(sing-box version 2>/dev/null | grep 'sing-box version' | awk '{print $3}')
    echo -e "\033[0;36mINFO:\033[0m sing-box 已安装，版本：$current_version"
else
    echo -e "\033[0;33mINFO:\033[0m sing-box 未安装"
fi
