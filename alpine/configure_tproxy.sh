#!/bin/sh

# 配置参数
TPROXY_PORT=7895
ROUTING_MARK=666
PROXY_FWMARK=1
PROXY_ROUTE_TABLE=100
INTERFACE=$(ip route show default | awk '/default/ {print $5; exit}')

# 保留 IP 地址集合
ReservedIP4='{ 127.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.0.2.0/24, 198.51.100.0/24, 192.88.99.0/24, 192.168.0.0/16, 203.0.113.0/24, 224.0.0.0/4, 240.0.0.0/4, 255.255.255.255/32 }'
CustomBypassIP='{ 192.168.0.0/16, 10.0.0.0/8 }'

# 读取当前模式（兼容 BusyBox）
MODE=$(sed -n 's/^MODE=//p' /etc/sing-box/mode.conf)

check_route_exists() {
    ip route show table "$1" >/dev/null 2>&1
    return $?
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
        if ip route show table "$PROXY_ROUTE_TABLE" >/dev/null 2>&1; then
            return 0
        fi
        echo "等待 FIB 表加载中，等待 $i 秒..."
        i=$((i + 1))
    done
    echo "FIB 表加载失败，超出最大重试次数"
    return 1
}

clearSingboxRules() {
    nft list table inet sing-box >/dev/null 2>&1 && nft delete table inet sing-box
    ip rule del fwmark $PROXY_FWMARK lookup $PROXY_ROUTE_TABLE 2>/dev/null
    ip route del local default dev "${INTERFACE}" table $PROXY_ROUTE_TABLE 2>/dev/null
    echo "清理 sing-box 相关的防火墙规则"
}

if [ "$MODE" = "TProxy" ]; then
    echo "应用 TProxy 模式下的防火墙规则..."

    create_route_table_if_not_exists

    if ! wait_for_fib_table; then
        echo "FIB 表准备失败，退出脚本。"
        exit 1
    fi

    clearSingboxRules

    ip -f inet rule add fwmark $PROXY_FWMARK lookup $PROXY_ROUTE_TABLE
    ip -f inet route add local default dev "${INTERFACE}" table $PROXY_ROUTE_TABLE
    sysctl -w net.ipv4.ip_forward=1 > /dev/null

    mkdir -p /etc/sing-box/nft

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
        meta l4proto tcp socket transparent 1 meta mark set $PROXY_FWMARK accept
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

    nft -f /etc/sing-box/nft/nftables.conf
    nft list ruleset > /etc/nftables.conf

    echo "✅ TProxy 模式的防火墙规则已应用"
else
    echo "ℹ️ 当前模式为 TUN 模式，不需要应用防火墙规则"
fi
