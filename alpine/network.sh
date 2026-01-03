#!/bin/sh

CONF="/etc/network/interfaces"
RESOLV="/etc/resolv.conf"

pause() {
    echo
    read -p "按回车继续..."
}

read_val() {
    while :; do
        read -p "$1: " val
        [ -n "$val" ] && break
        echo "不能为空，请重新输入"
    done
    echo "$val"
}

status() {
    echo "=== 网络接口状态 ==="
    ip a
    echo
    echo "=== IPv4 路由 ==="
    ip r
    echo
    echo "=== IPv6 路由 ==="
    ip -6 r
}

restart_net() {
    rc-service networking restart
    echo "[OK] 网络服务已重启"
}

# ------------------配置函数------------------

# IPv4 DHCP + IPv6 SLAAC
set_dhcp() {
    # 保留 lo 段
    grep -A 10 "^auto lo" "$CONF" > "$CONF.tmp" 2>/dev/null

    # 覆盖 eth0 配置
    cat >> "$CONF.tmp" <<EOF
auto eth0
iface eth0 inet dhcp
iface eth0 inet6 auto
EOF

    mv "$CONF.tmp" "$CONF"
    echo "[OK] 已写入 eth0 DHCP + SLAAC 配置"
}

# IPv4 静态 + IPv6 自动
set_static4() {
    IP=$(read_val "IPv4 地址 (如 10.10.10.252/24)")
    GW=$(read_val "IPv4 网关 (如 10.10.10.253)")

    # 保留 lo 段
    grep -A 10 "^auto lo" "$CONF" > "$CONF.tmp" 2>/dev/null

    cat >> "$CONF.tmp" <<EOF
auto eth0
iface eth0 inet static
        address $IP
        gateway $GW
iface eth0 inet6 auto
EOF

    mv "$CONF.tmp" "$CONF"
    echo "[OK] 已写入 eth0 静态 IPv4 配置 + IPv6 自动"
}

# IPv6 静态
set_static6() {
    IP6=$(read_val "IPv6 地址 (如 fe80::252/64)")
    GW6=$(read_val "IPv6 网关 (如 fe80::1, 可留空)")

    grep -A 10 "^auto lo" "$CONF" > "$CONF.tmp" 2>/dev/null

    cat >> "$CONF.tmp" <<EOF
auto eth0
iface eth0 inet dhcp
iface eth0 inet6 static
        address $IP6
EOF

    [ -n "$GW6" ] && echo "        gateway $GW6" >> "$CONF.tmp"

    mv "$CONF.tmp" "$CONF"
    echo "[OK] 已写入 eth0 IPv6 静态配置"
}

# 设置 DNS
set_dns() {
    echo "# DNS 配置" > "$RESOLV"
    while :; do
        read -p "输入 DNS（留空结束）: " DNS
        [ -z "$DNS" ] && break
        echo "nameserver $DNS" >> "$RESOLV"
    done
    echo "[OK] DNS 配置完成"
}

# ------------------菜单------------------
menu() {
clear
cat <<EOF
=========== Alpine 网络管理 (eth0 + DNS) ===========
1) IPv4 DHCP + IPv6 SLAAC
2) IPv4 静态
3) IPv6 静态
4) 设置 DNS
5) 查看状态
6) 应用并重启网络
0) 退出
=======================================
EOF
}

# ------------------主循环------------------
while :; do
    menu
    read -p "请选择: " c
    case "$c" in
        1) set_dhcp; pause ;;
        2) set_static4; pause ;;
        3) set_static6; pause ;;
        4) set_dns; pause ;;
        5) status; pause ;;
        6) restart_net; pause ;;
        0) exit 0 ;;
        *) echo "无效选择"; pause ;;
    esac
done
