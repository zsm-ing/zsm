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

# ===== 配置参数 =====
PROXY_FWMARK=1
PROXY_ROUTE_TABLE=100
INTERFACE=$(ip route show default | awk '/default/ {print $5; exit}')

MODE=$(grep -E '^MODE=' /etc/sing-box/mode.conf | sed 's/^MODE=//')

# ===== 检查 nftables 命令 =====
if ! command -v nft >/dev/null 2>&1; then
    echo -e "\033[0;31m[ERROR]\033[0m nftables 未安装，请先 apk add nftables"
    exit 1
fi

# ===== 清理 TProxy 模式防火墙规则 =====
clearTProxyRules() {
    nft list table inet sing-box >/dev/null 2>&1 && nft delete table inet sing-box
    ip rule del fwmark $PROXY_FWMARK lookup $PROXY_ROUTE_TABLE 2>/dev/null || true
    ip route del local default dev "$INTERFACE" table $PROXY_ROUTE_TABLE 2>/dev/null || true
    echo "清理 TProxy 模式的防火墙规则"
}

# ===== 应用 TUN 模式规则 =====
if [ "$MODE" = "TUN" ]; then
    echo "应用 TUN 模式下的防火墙规则..."

    clearTProxyRules

    mkdir -p /etc/sing-box/tun

    cat > /etc/sing-box/tun/nftables.conf <<EOF
table inet sing-box {
    chain input {
        type filter hook input priority 0; policy accept;
    }
    chain forward {
        type filter hook forward priority 0; policy accept;
    }
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

    nft -f /etc/sing-box/tun/nftables.conf || { echo -e "\033[0;31m[ERROR]\033[0m 应用 TUN 防火墙规则失败"; exit 1; }

    nft list ruleset > /etc/nftables.conf

    echo "TUN 模式的防火墙规则已应用。"
else
    echo "当前模式不是 TUN 模式，跳过防火墙规则配置."
fi
