# ===== MikroTik RouterOS v7 家庭高大全 ERSC =====
# 场景：500M↓ / 50M↑ | IPv4 + IPv6 | 全场景 QoS | 基础入侵防护
# 假设：WAN=pppoe-out1  LAN=bridge-lan
# 使用前请确认接口名称

############################
# 一、基础参数
############################
:global WAN_IF "pppoe-out1"
:global LAN_IF "bridge-lan"

############################
# 二、DSCP 流量标记（IPv4）
############################
/ip firewall mangle
# 游戏 / 实时 UDP
add chain=forward protocol=udp packet-size=0-256 action=set-dscp new-dscp=46 comment="QoS EF Game/VoIP"

# DNS
add chain=forward protocol=udp dst-port=53 action=set-dscp new-dscp=18 comment="QoS AF21 DNS"

# HTTPS / 视频
add chain=forward protocol=tcp dst-port=443 action=set-dscp new-dscp=34 comment="QoS AF41 Video"

# BT / 下载
add chain=forward protocol=tcp dst-port=6881-6999 action=set-dscp new-dscp=8 comment="QoS CS1 Bulk"

############################
# 三、DSCP 流量标记（IPv6）
############################
/ipv6 firewall mangle
add chain=forward protocol=udp packet-size=0-256 action=set-dscp new-dscp=46 comment="QoS6 EF Game"
add chain=forward protocol=udp dst-port=53 action=set-dscp new-dscp=18 comment="QoS6 DNS"
add chain=forward protocol=tcp dst-port=443 action=set-dscp new-dscp=34 comment="QoS6 Video"

############################
# 四、CAKE 队列类型
############################
/queue type
add name=cake-up kind=cake cake-diffserv=diffserv4 cake-flowmode=triple-isolate cake-nat=yes
add name=cake-down kind=cake cake-diffserv=diffserv4 cake-flowmode=triple-isolate

############################
# 五、Simple Queue（上下行）
############################
/queue simple
add name=UPLOAD target=$WAN_IF max-limit=45M/45M queue=cake-up
add name=DOWNLOAD target=$LAN_IF max-limit=470M/470M queue=cake-down

############################
# 六、FastTrack（仅普通流量）
############################
/ip firewall filter
add chain=forward action=fasttrack-connection connection-state=established,related comment="FastTrack Normal"
add chain=forward connection-state=established,related action=accept

############################
# 七、WAN 入侵防护（IPv4）
############################
/ip firewall filter
add chain=input connection-state=invalid action=drop comment="Drop Invalid"
add chain=input in-interface=$WAN_IF protocol=tcp tcp-flags=syn connection-limit=30,32 action=drop comment="Anti Scan"
add chain=input protocol=tcp tcp-flags=syn limit=100,5 action=accept
add chain=input protocol=tcp tcp-flags=syn action=drop comment="SYN Flood"
add chain=input in-interface=$WAN_IF action=drop comment="Drop WAN Input"

############################
# 八、IPv6 防护
############################
/ipv6 firewall filter
add chain=input connection-state=invalid action=drop
add chain=input protocol=icmpv6 action=accept
add chain=input in-interface=$WAN_IF action=drop

############################
# 九、系统优化
############################
/ip settings set tcp-syncookies=yes
/ipv6 settings set accept-router-advertisements=yes

# ===== 结束 =====
