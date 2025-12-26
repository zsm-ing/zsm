#!/bin/sh
# DIY defaults for ImmortalWRT (LXC)

# 写入 uci-defaults
mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/99-network << 'EOF'
#!/bin/sh

uci batch << EOT
# LAN 基本信息
set network.lan.proto='static'
set network.lan.ipaddr='10.10.10.250'
set network.lan.netmask='255.255.255.0'
set network.lan.gateway='10.10.10.253'

# DNS
del network.lan.dns
add_list network.lan.dns='223.5.5.5'
add_list network.lan.dns='8.8.8.8'

commit network
EOT

exit 0
EOF

chmod +x files/etc/uci-defaults/99-network
