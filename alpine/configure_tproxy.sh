#!/bin/bash
set -Eeuo pipefail

# ===== Alpine 系统检测 =====
if [ ! -f /etc/os-release ] || ! grep -qi '^ID=alpine' /etc/os-release; then
    echo -e "\033[0;31m[ERROR]\033[0m 本脚本仅支持 Alpine Linux"
    exit 1
fi

# ===== 检查 root =====
if [ "$(id -u)" != "0" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m 此脚本需要 root 权限"
    exit 1
fi

# ===== 配置参数 =====
TPROXY_PORT=7895
ROUTING_MARK=666
PROXY_FWMARK=1
PROXY_ROUTE_TABLE=100
INTERFACE=$(ip route show default | awk '/default/ {print $5; exit}')

ReservedIP4='{ 127.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.0.2.0/24, 198.51.100.0/24, 192.88.99.0/24, 192.168.0.0/16, 203.0.113.0/24, 224.0.0.0/4, 240.0.0.0/4, 255.255.255.255/32 }'
CustomBypassIP='{ 192.168.0.0/16, 10.0.0.0/8 }'

MODE=$(grep -E '^MODE=' /etc/sing-box/mode.conf | sed 's/^MODE=//')

# ===== 检查 nftables 命令 =====
if ! command -v nft >/dev/null 2>&1; then
    echo -e "\033[0;31m[ERROR]\033[0m nftables 未安装，请先 apk add nftables"
    exit 1
fi

# ===== 路由表相关函数 =====
check_route_exists() {
    ip route show table "$1" >/dev/null 2>&1
}

create_route_table_if_not_exists() {
    if ! check_route_exists "$PROXY_ROUTE_TABLE"; then
        echo "路由表不存在，正在创建..."
        ip route add local default dev "$INTERFACE" table "$PROXY_ROUTE_TABLE" || { echo "创建路由表失败"; exit 1; }
    fi
}

wait_for_fib_table() {
    i=1
    while [ $i -le 10 ]; do
        if check_route_exists "$PROXY_ROUTE_TABLE"; then
            return 0
        fi
        echo "等待 FIB 表加载中，等待 $i 秒..."
        sleep 1
        i=$((i + 1))
    done
    echo "FIB 表加载失败"
    return 1
}

clearSingboxRules() {
    nft list table inet sing-box >/dev/null 2>&1 && nft delete table inet sing-box
    ip rule del fwmark $PROXY_FWMARK lookup $PROXY_ROUTE_TABLE 2>/dev/null || true
    ip route del local default dev "$INTERFACE" table $PROXY_ROUTE_TABLE 2>/dev/null || true
    echo "清理 sing-box 相关防火墙规则"
}

# ===== 仅在 TProxy 模式下应用 =====
if [ "$MODE" = "TProxy" ]; then
    echo "应用 TProxy 模式下的防火墙规则..."

    create_route_table_if_not_exists
    wait_for_fib_table || { echo "FIB 表准备失败"; exit 1; }

    clearSingboxRules

    ip rule add fwmark $PROXY_FWMARK table $PROXY_ROUTE_TABLE
    ip route add local default dev "$INTERFACE" table $PROXY_ROUTE_TABLE
    sysctl -w net.ipv4.ip_forward=1 > /dev/null

    mkdir -p /etc/sing-box/nft
    nft add table inet sing-box

    cat > /etc/sing-box/nft/nftables.conf <<EOF
table inet sing-box {
    set RESERVED_IPSET {
        type ipv4_addr
        flags interval
        auto-merge
        elements = $ReservedIP4
    }

    chain prerouting_tproxy {
        type filter hook prerouting priority mangle; policy accept;
        meta l4proto { tcp, udp } th dport 53 tproxy to :$TPROXY_PORT accept
        ip daddr $CustomBypassIP accept
        fib daddr type local meta l4proto { tcp, udp } th dport $TPROXY_PORT reject with icmpx type host-unreachable
        fib daddr type local accept
        ip daddr @RESERVED_IPSET accept
        ct status dnat accept comment "Allow forwarded traffic"
        meta l4proto { tcp, udp } tproxy to :$TPROXY_PORT meta mark set $PROXY_FWMARK
    }

    chain output_tproxy {
        type route hook output priority mangle; policy accept;
        meta oifname "lo" accept
        meta mark $ROUTING_MARK accept
        meta l4proto { tcp, udp } th dport 53 meta mark set $PROXY_FWMARK
        udp dport { netbios-ns, netbios-dgm, netbios-ssn } accept
        ip daddr $CustomBypassIP accept
        fib daddr type local accept
        ip daddr @RESERVED_IPSET accept
        meta l4proto { tcp, udp } meta mark set $PROXY_FWMARK
    }
}
EOF

    nft -f /etc/sing-box/nft/nftables.conf || { echo "应用防火墙规则失败"; exit 1; }
    nft list ruleset > /etc/nftables.conf

    echo "TProxy 模式防火墙规则已应用。"
else
    echo "当前模式为 TUN 模式，不应用防火墙规则."
fi
