#!/bin/sh
# Alpine LXC 网络管理菜单脚本
# 支持接口选择、IPv4/IPv6/DNS/固定本地 IPv6
# Author: zsm

CONF="/etc/network/interfaces"
RESOLV="/etc/resolv.conf"

pause() {
    echo
    read -p "按回车继续..."
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

read_val() {
    while :; do
        read -p "$1: " val
        [ -n "$val" ] && break
        echo "不能为空，请重新输入"
    done
    echo "$val"
}

write_lo() {
    cat > "$CONF" <<EOF
auto lo
iface lo inet loopback

EOF
}

restart_net() {
    rc-service networking restart
    echo "[OK] 网络服务已重启"
}

# ------------------接口选择------------------
select_iface() {
    IFACES=$(ip -o link show | awk -F: '/: e/{print $2}' | tr -d ' ')
    count=1
    echo "请选择网络接口："
    for i in $IFACES; do
        echo "  $count) $i"
        count=$((count + 1))
    done

    while :; do
        read -p "输入编号: " choice
        if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -lt "$count" ] 2>/dev/null; then
            index=1
            for iface in $IFACES; do
                if [ "$index" -eq "$choice" ]; then
                    echo "$iface"
                    return
                fi
                index=$((index + 1))
            done
        fi
        echo "输入无效，请重新选择编号"
    done
}

# ------------------配置函数------------------

# IPv4 DHCP + IPv6 SLAAC
set_dhcp() {
    IFACE=$(select_iface)
    write_lo
    cat >> "$CONF" <<EOF
auto $IFACE
iface $IFACE inet dhcp
iface $IFACE inet6 auto
EOF
    echo "[OK] 已写入 DHCP + SLAAC 配置"
}

# IPv4 静态
set_static4() {
    IFACE=$(select_iface)
    IP=$(read_val "IPv4 地址")
    MASK=$(read_val "子网掩码")
    GW=$(read_val "IPv4 网关")

    write_lo
    cat >> "$CONF" <<EOF
auto $IFACE
iface $IFACE inet static
    address $IP
    netmask $MASK
    gateway $GW

iface $IFACE inet6 auto
EOF
    echo "[OK] 已写入 IPv4 静态配置"
}

# IPv6 静态
set_static6() {
    IFACE=$(select_iface)
    IP6=$(read_val "IPv6 地址（不含 /64）")
    GW6=$(read_val "IPv6 网关（可 fe80::1）")

    write_lo
    cat >> "$CONF" <<EOF
auto $IFACE
iface $IFACE inet dhcp

iface $IFACE inet6 static
    address $IP6
    netmask 64
    gateway $GW6
EOF
    echo "[OK] 已写入 IPv6 静态配置"
}

# 固定本地 IPv6
set_local_ipv6() {
    IFACE=$(select_iface)
    IP6=$(read_val "请输入本地 IPv6 地址（例如 240e:xxxx::252/64）")

    # 临时立即生效
    ip -6 addr flush dev "$IFACE"
    ip -6 addr add "$IP6" dev "$IFACE"
    echo "[OK] 临时添加 IPv6 地址 $IP6"

    # 永久写入 interfaces
    grep -q "$IP6" "$CONF" 2>/dev/null || \
    sed -i "/iface $IFACE inet6/ a\
    pre-up ip -6 addr flush dev $IFACE\n\
    up ip -6 addr add $IP6 dev $IFACE" "$CONF"

    echo "[OK] 永久配置已写入 $CONF"
}

# DNS 设置
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
=========== Alpine 网络管理 ===========
动态菜单，接口可选择

1) IPv4 DHCP + IPv6 SLAAC
2) IPv4 静态
3) IPv6 静态
4) 固定本地 IPv6 地址
5) 设置 DNS
6) 查看状态
7) 应用并重启网络
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
        4) set_local_ipv6; pause ;;
        5) set_dns; pause ;;
        6) status; pause ;;
        7) restart_net; pause ;;
        0) exit 0 ;;
        *) echo "无效选择"; pause ;;
    esac
done
