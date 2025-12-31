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

# ===== 检查 nftables 是否存在 =====
if ! command -v nft >/dev/null 2>&1; then
    echo -e "\033[0;33mINFO:\033[0m 未检测到 nft 命令，跳过防火墙规则清理"
    exit 0
fi

# ===== 删除 sing-box 表 =====
if nft list table inet sing-box >/dev/null 2>&1; then
    nft delete table inet sing-box
    echo -e "\033[0;36mINFO:\033[0m sing-box 相关防火墙规则已清理"
else
    echo -e "\033[0;36mINFO:\033[0m 没有检测到 sing-box 防火墙规则，无需清理"
fi

# ===== 服务停止提示 =====
echo -e "\033[0;36mINFO:\033[0m sing-box 服务已停止"
